import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/cache_data.dart';
import '../models/query_options.dart';
import '../models/server.dart';

class ServerImportNotice {
  final String name;
  final String ip;
  final String detail;

  const ServerImportNotice({
    required this.name,
    required this.ip,
    required this.detail,
  });
}

class ServerConfigExportResult {
  final String path;
  final int exportedCount;

  const ServerConfigExportResult({
    required this.path,
    required this.exportedCount,
  });
}

class ServerConfigImportResult {
  final int importedCount;
  final int duplicateSkippedCount;
  final int renamedCount;
  final int invalidCount;
  final int limitSkippedCount;
  final List<ServerImportNotice> renamedEntries;
  final List<ServerImportNotice> skippedEntries;

  const ServerConfigImportResult({
    required this.importedCount,
    required this.duplicateSkippedCount,
    required this.renamedCount,
    required this.invalidCount,
    required this.limitSkippedCount,
    this.renamedEntries = const [],
    this.skippedEntries = const [],
  });
}

class StorageService {
  static const String _databaseName = 'shellguard.db';
  static const int _databaseVersion = 5;
  static const String _serversFileName = 'servers.json';
  static const String _cacheFileName = 'cache.json';
  static const String _selectedServerFileName = 'selected_server.json';
  static const String _groupsFileName = 'groups.json';
  static const String _defaultGroup = '默认分组';
  static const String _selectedServerKey = 'selected_server';
  static const String _legacyMigratedKey = 'legacy_json_migrated';

  Database? _database;

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<Directory> get _dataDirectory async {
    final dir = Directory(p.join(Directory.current.path, 'data'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Database> get _db async {
    if (_database != null) {
      return _database!;
    }

    final dataDir = await _dataDirectory;
    final databasePath = p.join(dataDir.path, _databaseName);
    _database = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: (db, _) async => _createTables(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createUsageTables(db);
          }
          if (oldVersion < 3) {
            await _createAiTables(db);
          }
          if (oldVersion < 4) {
            await _upgradeAiTablesV4(db);
          }
          if (oldVersion < 5) {
            await _createAiSessionTables(db);
          }
        },
      ),
    );
    await _createTables(_database!);
    await _migrateLegacyJsonIfNeeded(_database!);
    return _database!;
  }

  Future<void> _createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        ip TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        private_key TEXT,
        group_name TEXT NOT NULL,
        tags_json TEXT NOT NULL,
        is_online INTEGER NOT NULL DEFAULT 0,
        os_info TEXT,
        kernel_version TEXT,
        uptime TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS server_cache (
        server_id TEXT PRIMARY KEY,
        cache_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_state (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS groups_table (
        name TEXT PRIMARY KEY
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS operation_logs (
        id TEXT PRIMARY KEY,
        command TEXT NOT NULL,
        server_id TEXT NOT NULL,
        server_name TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        result TEXT NOT NULL
      )
    ''');

    await _createUsageTables(db);
    await _createAiTables(db);
    await _createAiSessionTables(db);

    await db.insert(
      'groups_table',
      {'name': _defaultGroup},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _createUsageTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS usage_events (
        id TEXT PRIMARY KEY,
        server_id TEXT NOT NULL,
        page_key TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS server_capabilities (
        server_id TEXT PRIMARY KEY,
        docker_installed INTEGER,
        last_checked TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createAiTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS llm_provider_configs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key TEXT NOT NULL,
        model TEXT NOT NULL,
        max_tokens INTEGER NOT NULL DEFAULT 4096,
        enabled INTEGER NOT NULL DEFAULT 1,
        is_default INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_tasks (
        id TEXT PRIMARY KEY,
        server_id TEXT NOT NULL,
        server_name TEXT NOT NULL,
        prompt TEXT NOT NULL,
        analysis TEXT NOT NULL,
        final_answer TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_steps (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        title TEXT NOT NULL,
        command TEXT NOT NULL,
        summary TEXT NOT NULL,
        status TEXT NOT NULL,
        risk_level TEXT NOT NULL,
        requires_confirmation INTEGER NOT NULL DEFAULT 0,
        order_index INTEGER NOT NULL,
        output TEXT NOT NULL DEFAULT '',
        error_output TEXT NOT NULL DEFAULT '',
        started_at TEXT,
        finished_at TEXT
      )
    ''');
  }

  Future<void> _upgradeAiTablesV4(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE ai_tasks ADD COLUMN final_answer TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _createAiSessionTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_sessions (
        id TEXT PRIMARY KEY,
        server_id TEXT NOT NULL,
        server_name TEXT NOT NULL,
        title TEXT NOT NULL,
        compressed_context TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        final_answer TEXT NOT NULL DEFAULT '',
        analysis TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_message_steps (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        title TEXT NOT NULL,
        command TEXT NOT NULL,
        summary TEXT NOT NULL,
        status TEXT NOT NULL,
        risk_level TEXT NOT NULL,
        requires_confirmation INTEGER NOT NULL DEFAULT 0,
        order_index INTEGER NOT NULL,
        output TEXT NOT NULL DEFAULT '',
        error_output TEXT NOT NULL DEFAULT '',
        started_at TEXT,
        finished_at TEXT
      )
    ''');
  }

  Future<void> _migrateLegacyJsonIfNeeded(Database db) async {
    final migrated = await db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: [_legacyMigratedKey],
      limit: 1,
    );
    if (migrated.isNotEmpty) {
      return;
    }

    final dataDir = await _dataDirectory;
    final serversFile = File(p.join(dataDir.path, _serversFileName));
    final cacheFile = File(p.join(dataDir.path, _cacheFileName));
    final selectedServerFile = File(p.join(dataDir.path, _selectedServerFileName));
    final groupsFile = File(p.join(dataDir.path, _groupsFileName));

    await db.transaction((txn) async {
      if (await serversFile.exists()) {
        final raw = await serversFile.readAsString();
        final List<dynamic> list = json.decode(raw) as List<dynamic>;
        for (final item in list.cast<Map<String, dynamic>>()) {
          final server = Server.fromJson(item);
          await txn.insert(
            'servers',
            _serverToRow(server),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await txn.insert(
            'groups_table',
            {'name': server.group},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      if (await cacheFile.exists()) {
        final raw = await cacheFile.readAsString();
        final Map<String, dynamic> map = json.decode(raw) as Map<String, dynamic>;
        for (final entry in map.entries) {
          await txn.insert(
            'server_cache',
            {
              'server_id': entry.key,
              'cache_json': json.encode(entry.value),
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      if (await selectedServerFile.exists()) {
        final raw = await selectedServerFile.readAsString();
        final Map<String, dynamic> data = json.decode(raw) as Map<String, dynamic>;
        final serverId = data['serverId']?.toString();
        if (serverId != null && serverId.isNotEmpty) {
          await txn.insert(
            'app_state',
            {'key': _selectedServerKey, 'value': serverId},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      if (await groupsFile.exists()) {
        final raw = await groupsFile.readAsString();
        final List<dynamic> list = json.decode(raw) as List<dynamic>;
        for (final group in list) {
          final groupName = group.toString();
          if (groupName.isEmpty) continue;
          await txn.insert(
            'groups_table',
            {'name': groupName},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      await txn.insert(
        'app_state',
        {'key': _legacyMigratedKey, 'value': 'true'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> saveServers(List<Server> servers) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('servers');
      final groupNames = <String>{_defaultGroup};
      for (final server in servers) {
        await txn.insert(
          'servers',
          _serverToRow(server),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        groupNames.add(server.group);
      }

      for (final group in groupNames) {
        await txn.insert(
          'groups_table',
          {'name': group},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<Server>> loadServers() async {
    try {
      final db = await _db;
      final rows = await db.query('servers', orderBy: 'name COLLATE NOCASE');
      return rows.map(_serverFromRow).toList();
    } catch (_) {
      return <Server>[];
    }
  }

  Future<ServerConfigExportResult> exportServersToJson({
    required List<Server> servers,
    required String targetPath,
  }) async {
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    final payload = <String, Object?>{
      'schema': 'shellguard_server_list',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'serverCount': servers.length,
      'servers': servers.map(_serverToExportJson).toList(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return ServerConfigExportResult(
      path: file.path,
      exportedCount: servers.length,
    );
  }

  Future<ServerConfigImportResult> importServersFromJson({
    required String filePath,
    int? maxAdditionalServers,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const FormatException('导入文件不存在');
    }

    final raw = await file.readAsString();
    final decoded = json.decode(raw);
    final entries = _extractImportEntries(decoded);
    final existingServers = await loadServers();
    final existingGroups = await loadGroups();
    final mergedServers = List<Server>.from(existingServers);
    final groupNames = <String>{...existingGroups, _defaultGroup};
    final existingNames = mergedServers
        .map((server) => server.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final existingKeys = mergedServers.map(_serverIdentityKey).toSet();
    final existingIps = mergedServers.map((server) => _normalizeIp(server.ip)).toSet();
    final seenImportKeys = <String>{};
    final renamedEntries = <ServerImportNotice>[];
    final skippedEntries = <ServerImportNotice>[];
    var importedCount = 0;
    var duplicateSkippedCount = 0;
    var renamedCount = 0;
    var invalidCount = 0;
    var limitSkippedCount = 0;
    var remainingSlots = maxAdditionalServers ?? 1 << 20;
    var importSequence = 0;

    for (final entry in entries) {
      final normalized = _normalizeImportEntry(entry);
      if (normalized == null) {
        invalidCount++;
        continue;
      }

      final identityKey = _serverIdentityKey(normalized);
      if (existingKeys.contains(identityKey) || seenImportKeys.contains(identityKey)) {
        duplicateSkippedCount++;
        skippedEntries.add(
          ServerImportNotice(
            name: normalized.name,
            ip: normalized.ip,
            detail: '与本地或导入文件中的现有服务器重复，已跳过',
          ),
        );
        continue;
      }

      if (remainingSlots <= 0) {
        limitSkippedCount++;
        skippedEntries.add(
          ServerImportNotice(
            name: normalized.name,
            ip: normalized.ip,
            detail: '超过当前版本服务器数量上限，未导入',
          ),
        );
        continue;
      }

      final normalizedIp = _normalizeIp(normalized.ip);
      final baseName = normalized.name.trim().isEmpty ? normalized.ip : normalized.name.trim();
      var finalName = baseName;
      if (existingNames.contains(baseName) || existingIps.contains(normalizedIp)) {
        finalName = _buildImportedServerName(
          baseName: baseName,
          ip: normalized.ip,
          existingNames: existingNames,
        );
      }

      if (finalName != baseName) {
        renamedCount++;
        renamedEntries.add(
          ServerImportNotice(
            name: baseName,
            ip: normalized.ip,
            detail: '已重命名为 $finalName',
          ),
        );
      }

      final server = normalized.copyWith(
        id: _generateImportedServerId(importSequence++),
        name: finalName,
        isOnline: false,
        osInfo: null,
        kernelVersion: null,
        uptime: null,
      );
      mergedServers.add(server);
      groupNames.add(server.group.trim().isEmpty ? _defaultGroup : server.group.trim());
      existingNames.add(server.name);
      existingKeys.add(identityKey);
      existingIps.add(normalizedIp);
      seenImportKeys.add(identityKey);
      importedCount++;
      remainingSlots--;
    }

    if (importedCount > 0) {
      await saveServers(mergedServers);
      await saveGroups(groupNames.toList());
    }

    return ServerConfigImportResult(
      importedCount: importedCount,
      duplicateSkippedCount: duplicateSkippedCount,
      renamedCount: renamedCount,
      invalidCount: invalidCount,
      limitSkippedCount: limitSkippedCount,
      renamedEntries: renamedEntries,
      skippedEntries: skippedEntries,
    );
  }

  Future<void> saveCache(CacheData cache) async {
    final db = await _db;
    await db.insert(
      'server_cache',
      {
        'server_id': cache.serverId,
        'cache_json': json.encode(cache.toJson()),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CacheData?> loadCache(String serverId) async {
    try {
      final db = await _db;
      final rows = await db.query(
        'server_cache',
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return CacheData.fromJson(
        json.decode(rows.first['cache_json']! as String) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteCache(String serverId) async {
    final db = await _db;
    await db.delete('server_cache', where: 'server_id = ?', whereArgs: [serverId]);
  }

  Future<void> clearAllCache() async {
    final db = await _db;
    await db.delete('server_cache');
  }

  Future<String?> loadSelectedServer() async {
    try {
      final db = await _db;
      final rows = await db.query(
        'app_state',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [_selectedServerKey],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSelectedServer(String serverId) async {
    final db = await _db;
    await db.insert(
      'app_state',
      {'key': _selectedServerKey, 'value': serverId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> loadGroups() async {
    try {
      final db = await _db;
      final rows = await db.query('groups_table', orderBy: 'name COLLATE NOCASE');
      final groups = rows
          .map((row) => row['name']!.toString())
          .where((name) => name.isNotEmpty)
          .toList();
      if (!groups.contains(_defaultGroup)) {
        groups.insert(0, _defaultGroup);
      }
      return groups;
    } catch (_) {
      return <String>[_defaultGroup];
    }
  }

  Future<void> saveGroups(List<String> groups) async {
    final db = await _db;
    final safeGroups = {
      _defaultGroup,
      ...groups.where((group) => group.trim().isNotEmpty).map((group) => group.trim()),
    }.toList()
      ..sort();

    await db.transaction((txn) async {
      await txn.delete('groups_table');
      for (final group in safeGroups) {
        await txn.insert(
          'groups_table',
          {'name': group},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> saveOperationLog(OperationLog log) async {
    final db = await _db;
    await _purgeExpiredLogs(db);
    await db.insert(
      'operation_logs',
      {
        'id': log.id,
        'command': log.command,
        'server_id': log.serverId,
        'server_name': log.serverName,
        'timestamp': log.timestamp.toIso8601String(),
        'result': log.result,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addUsageEvent({
    required String serverId,
    required String pageKey,
    DateTime? timestamp,
  }) async {
    final db = await _db;
    final ts = timestamp ?? DateTime.now();
    await db.insert(
      'usage_events',
      {
        'id': '${serverId}_${pageKey}_${ts.microsecondsSinceEpoch}',
        'server_id': serverId,
        'page_key': pageKey,
        'timestamp': ts.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, int>> getUsageScore({
    required Duration window,
  }) async {
    final db = await _db;
    final cutoff = DateTime.now().subtract(window).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT server_id || ':' || page_key AS usage_key, COUNT(*) AS usage_count
      FROM usage_events
      WHERE timestamp >= ?
      GROUP BY server_id, page_key
      ''',
      [cutoff],
    );

    final result = <String, int>{};
    for (final row in rows) {
      result[row['usage_key']! as String] = (row['usage_count'] as int?) ?? 0;
    }
    return result;
  }

  Future<void> upsertCapability({
    required String serverId,
    bool? dockerInstalled,
    required DateTime checkedAt,
  }) async {
    final db = await _db;
    await db.insert(
      'server_capabilities',
      {
        'server_id': serverId,
        'docker_installed': dockerInstalled == null ? null : (dockerInstalled ? 1 : 0),
        'last_checked': checkedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCapability(String serverId) async {
    final db = await _db;
    final rows = await db.query(
      'server_capabilities',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return {
      'serverId': row['server_id'],
      'dockerInstalled': row['docker_installed'] == null
          ? null
          : ((row['docker_installed'] as int?) ?? 0) == 1,
      'lastChecked': row['last_checked'],
    };
  }

  Future<List<OperationLog>> loadRecentOperationLogs({
    String? serverId,
    int limit = 50,
  }) async {
    final db = await _db;
    await _purgeExpiredLogs(db);
    final rows = await db.query(
      'operation_logs',
      where: serverId == null ? null : 'server_id = ?',
      whereArgs: serverId == null ? null : [serverId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return rows.map((row) {
      return OperationLog(
        id: row['id']! as String,
        command: row['command']! as String,
        serverId: row['server_id']! as String,
        serverName: row['server_name']! as String,
        timestamp: DateTime.parse(row['timestamp']! as String),
        result: row['result']! as String,
      );
    }).toList();
  }

  Future<List<LlmProviderConfig>> loadLlmProviderConfigs() async {
    final db = await _db;
    final rows = await db.query(
      'llm_provider_configs',
      orderBy: 'is_default DESC, name COLLATE NOCASE',
    );
    return rows.map((row) {
      return LlmProviderConfig(
        id: row['id']! as String,
        name: row['name']! as String,
        baseUrl: row['base_url']! as String,
        apiKey: row['api_key']! as String,
        model: row['model']! as String,
        maxTokens: (row['max_tokens'] as int?) ?? 4096,
        enabled: ((row['enabled'] as int?) ?? 0) == 1,
        isDefault: ((row['is_default'] as int?) ?? 0) == 1,
      );
    }).toList();
  }

  Future<void> saveLlmProviderConfig(LlmProviderConfig config) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (config.isDefault) {
        await txn.update('llm_provider_configs', {'is_default': 0});
      }
      await txn.insert(
        'llm_provider_configs',
        {
          'id': config.id,
          'name': config.name,
          'base_url': config.baseUrl,
          'api_key': config.apiKey,
          'model': config.model,
          'max_tokens': config.maxTokens,
          'enabled': config.enabled ? 1 : 0,
          'is_default': config.isDefault ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteLlmProviderConfig(String id) async {
    final db = await _db;
    await db.delete('llm_provider_configs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveAiTask(AiTaskRecord task) async {
    final db = await _db;
    await db.insert(
      'ai_tasks',
      {
        'id': task.id,
        'server_id': task.serverId,
        'server_name': task.serverName,
        'prompt': task.prompt,
        'analysis': task.analysis,
        'final_answer': task.finalAnswer,
        'status': task.status.name,
        'error_message': task.errorMessage,
        'created_at': task.createdAt.toIso8601String(),
        'updated_at': task.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveAiSteps(List<AiStepRecord> steps) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final step in steps) {
        await txn.insert(
          'ai_steps',
          {
            'id': step.id,
            'task_id': step.taskId,
            'title': step.title,
            'command': step.command,
            'summary': step.summary,
            'status': step.status.name,
            'risk_level': step.riskLevel.name,
            'requires_confirmation': step.requiresConfirmation ? 1 : 0,
            'order_index': step.orderIndex,
            'output': step.output,
            'error_output': step.errorOutput,
            'started_at': step.startedAt?.toIso8601String(),
            'finished_at': step.finishedAt?.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<AiTaskRecord>> loadAiTasks({
    String? serverId,
    int limit = 20,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'ai_tasks',
      where: serverId == null ? null : 'server_id = ?',
      whereArgs: serverId == null ? null : [serverId],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map((row) {
      return AiTaskRecord(
        id: row['id']! as String,
        serverId: row['server_id']! as String,
        serverName: row['server_name']! as String,
        prompt: row['prompt']! as String,
        analysis: row['analysis']! as String,
        finalAnswer: (row['final_answer'] as String?) ?? '',
        status: AiTaskStatus.values.byName(row['status']! as String),
        errorMessage: row['error_message'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
    }).toList();
  }

  Future<List<AiStepRecord>> loadAiSteps(String taskId) async {
    final db = await _db;
    final rows = await db.query(
      'ai_steps',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'order_index ASC',
    );
    return rows.map((row) {
      return AiStepRecord(
        id: row['id']! as String,
        taskId: row['task_id']! as String,
        title: row['title']! as String,
        command: row['command']! as String,
        summary: row['summary']! as String,
        status: AiStepStatus.values.byName(row['status']! as String),
        riskLevel: AiRiskLevel.values.byName(row['risk_level']! as String),
        requiresConfirmation: ((row['requires_confirmation'] as int?) ?? 0) == 1,
        orderIndex: row['order_index']! as int,
        output: (row['output'] as String?) ?? '',
        errorOutput: (row['error_output'] as String?) ?? '',
        startedAt: row['started_at'] == null
            ? null
            : DateTime.tryParse(row['started_at']! as String),
        finishedAt: row['finished_at'] == null
            ? null
            : DateTime.tryParse(row['finished_at']! as String),
      );
    }).toList();
  }

  Future<void> deleteAiTask(String taskId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'ai_steps',
        where: 'task_id = ?',
        whereArgs: [taskId],
      );
      await txn.delete(
        'ai_tasks',
        where: 'id = ?',
        whereArgs: [taskId],
      );
    });
  }

  Future<void> saveAiSession(AiSessionRecord session) async {
    final db = await _db;
    await db.insert(
      'ai_sessions',
      {
        'id': session.id,
        'server_id': session.serverId,
        'server_name': session.serverName,
        'title': session.title,
        'compressed_context': session.compressedContext,
        'status': session.status.name,
        'error_message': session.errorMessage,
        'created_at': session.createdAt.toIso8601String(),
        'updated_at': session.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> renameAiSession(String sessionId, String title) async {
    final db = await _db;
    await db.update(
      'ai_sessions',
      {
        'title': title.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<AiSessionRecord>> loadAiSessions({
    String? serverId,
    int limit = 30,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'ai_sessions',
      where: serverId == null ? null : 'server_id = ?',
      whereArgs: serverId == null ? null : [serverId],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map((row) {
      return AiSessionRecord(
        id: row['id']! as String,
        serverId: row['server_id']! as String,
        serverName: row['server_name']! as String,
        title: row['title']! as String,
        compressedContext: (row['compressed_context'] as String?) ?? '',
        status: AiTaskStatus.values.byName(row['status']! as String),
        errorMessage: row['error_message'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
    }).toList();
  }

  Future<void> saveAiMessage(AiMessageRecord message) async {
    final db = await _db;
    await db.insert(
      'ai_messages',
      {
        'id': message.id,
        'session_id': message.sessionId,
        'role': message.role.name,
        'content': message.content,
        'final_answer': message.finalAnswer,
        'analysis': message.analysis,
        'status': message.status.name,
        'error_message': message.errorMessage,
        'created_at': message.createdAt.toIso8601String(),
        'updated_at': message.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AiMessageRecord>> loadAiMessages(String sessionId) async {
    final db = await _db;
    final rows = await db.query(
      'ai_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
    return rows.map((row) {
      return AiMessageRecord(
        id: row['id']! as String,
        sessionId: row['session_id']! as String,
        role: AiMessageRole.values.byName(row['role']! as String),
        content: row['content']! as String,
        finalAnswer: (row['final_answer'] as String?) ?? '',
        analysis: (row['analysis'] as String?) ?? '',
        status: AiTaskStatus.values.byName(row['status']! as String),
        errorMessage: row['error_message'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
    }).toList();
  }

  Future<void> saveAiMessageSteps(
    String messageId,
    List<AiStepRecord> steps,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (final step in steps) {
        await txn.insert(
          'ai_message_steps',
          {
            'id': step.id,
            'message_id': messageId,
            'title': step.title,
            'command': step.command,
            'summary': step.summary,
            'status': step.status.name,
            'risk_level': step.riskLevel.name,
            'requires_confirmation': step.requiresConfirmation ? 1 : 0,
            'order_index': step.orderIndex,
            'output': step.output,
            'error_output': step.errorOutput,
            'started_at': step.startedAt?.toIso8601String(),
            'finished_at': step.finishedAt?.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<AiStepRecord>> loadAiMessageSteps(String messageId) async {
    final db = await _db;
    final rows = await db.query(
      'ai_message_steps',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'order_index ASC',
    );
    return rows.map((row) {
      return AiStepRecord(
        id: row['id']! as String,
        taskId: row['message_id']! as String,
        title: row['title']! as String,
        command: row['command']! as String,
        summary: row['summary']! as String,
        status: AiStepStatus.values.byName(row['status']! as String),
        riskLevel: AiRiskLevel.values.byName(row['risk_level']! as String),
        requiresConfirmation: ((row['requires_confirmation'] as int?) ?? 0) == 1,
        orderIndex: row['order_index']! as int,
        output: (row['output'] as String?) ?? '',
        errorOutput: (row['error_output'] as String?) ?? '',
        startedAt: row['started_at'] == null
            ? null
            : DateTime.tryParse(row['started_at']! as String),
        finishedAt: row['finished_at'] == null
            ? null
            : DateTime.tryParse(row['finished_at']! as String),
      );
    }).toList();
  }

  Future<void> deleteAiSession(String sessionId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'ai_messages',
        columns: ['id'],
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      for (final row in rows) {
        await txn.delete(
          'ai_message_steps',
          where: 'message_id = ?',
          whereArgs: [row['id']],
        );
      }
      await txn.delete(
        'ai_messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'ai_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  Future<void> _purgeExpiredLogs(Database db) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    await db.delete(
      'operation_logs',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  Future<List<ProcessInfo>> queryProcesses({
    required String serverId,
    required QueryOptions options,
  }) async {
    final cache = await loadCache(serverId);
    final keyword = options.keyword.trim().toLowerCase();
    final items = List<ProcessInfo>.from(cache?.processes ?? const <ProcessInfo>[]);
    final filtered = items.where((item) {
      if (keyword.isEmpty) {
        return true;
      }
      return item.name.toLowerCase().contains(keyword) ||
          item.pid.toString().contains(keyword) ||
          item.user.toLowerCase().contains(keyword) ||
          item.command.toLowerCase().contains(keyword) ||
          item.status.toLowerCase().contains(keyword);
    }).toList();
    filtered.sort((a, b) {
      switch (options.sortBy) {
        case 'pid':
          return _compareValues(a.pid, b.pid, options.ascending);
        case 'name':
          return _compareStrings(a.name, b.name, options.ascending);
        case 'memory':
          return _compareValues(
            a.memoryPercent,
            b.memoryPercent,
            options.ascending,
          );
        case 'status':
          return _compareStrings(a.status, b.status, options.ascending);
        case 'user':
          return _compareStrings(a.user, b.user, options.ascending);
        case 'cpu':
        default:
          return _compareValues(a.cpuPercent, b.cpuPercent, options.ascending);
      }
    });
    return filtered;
  }

  Future<List<PortInfo>> queryPorts({
    required String serverId,
    required QueryOptions options,
  }) async {
    final cache = await loadCache(serverId);
    final keyword = options.keyword.trim().toLowerCase();
    final items = List<PortInfo>.from(cache?.ports ?? const <PortInfo>[]);
    final filtered = items.where((item) {
      if (keyword.isEmpty) {
        return true;
      }
      return item.port.toLowerCase().contains(keyword) ||
          item.protocol.toLowerCase().contains(keyword) ||
          item.pid.toLowerCase().contains(keyword) ||
          item.processName.toLowerCase().contains(keyword) ||
          item.address.toLowerCase().contains(keyword);
    }).toList();
    filtered.sort((a, b) {
      switch (options.sortBy) {
        case 'protocol':
          return _compareStrings(a.protocol, b.protocol, options.ascending);
        case 'address':
          return _compareStrings(a.address, b.address, options.ascending);
        case 'pid':
          return _compareValues(
            _parseInt(a.pid),
            _parseInt(b.pid),
            options.ascending,
          );
        case 'processName':
          return _compareStrings(
            a.processName,
            b.processName,
            options.ascending,
          );
        case 'port':
        default:
          return _compareValues(
            _parseInt(a.port),
            _parseInt(b.port),
            options.ascending,
          );
      }
    });
    return filtered;
  }

  Future<List<ServiceInfo>> queryServices({
    required String serverId,
    required QueryOptions options,
  }) async {
    final cache = await loadCache(serverId);
    final keyword = options.keyword.trim().toLowerCase();
    final items = List<ServiceInfo>.from(cache?.services ?? const <ServiceInfo>[]);
    final filtered = items.where((item) {
      if (keyword.isEmpty) {
        return true;
      }
      return item.name.toLowerCase().contains(keyword) ||
          item.description.toLowerCase().contains(keyword) ||
          item.status.toLowerCase().contains(keyword);
    }).toList();
    filtered.sort((a, b) {
      switch (options.sortBy) {
        case 'status':
          return _compareStrings(a.status, b.status, options.ascending);
        case 'enabled':
          return _compareValues(
            a.isEnabled ? 1 : 0,
            b.isEnabled ? 1 : 0,
            options.ascending,
          );
        case 'description':
          return _compareStrings(
            a.description,
            b.description,
            options.ascending,
          );
        case 'name':
        default:
          return _compareStrings(a.name, b.name, options.ascending);
      }
    });
    return filtered;
  }

  Future<List<DockerContainer>> queryDockerContainers({
    required String serverId,
    required QueryOptions options,
  }) async {
    final cache = await loadCache(serverId);
    final keyword = options.keyword.trim().toLowerCase();
    final items = List<DockerContainer>.from(
      cache?.dockerContainers ?? const <DockerContainer>[],
    );
    final filtered = items.where((item) {
      if (keyword.isEmpty) {
        return true;
      }
      return item.name.toLowerCase().contains(keyword) ||
          item.image.toLowerCase().contains(keyword) ||
          item.status.toLowerCase().contains(keyword) ||
          item.ports.join(',').toLowerCase().contains(keyword);
    }).toList();
    filtered.sort((a, b) {
      switch (options.sortBy) {
        case 'image':
          return _compareStrings(a.image, b.image, options.ascending);
        case 'status':
          return _compareStrings(a.status, b.status, options.ascending);
        case 'cpu':
          return _compareValues(
            _parseLeadingDouble(a.cpuUsage),
            _parseLeadingDouble(b.cpuUsage),
            options.ascending,
          );
        case 'memory':
          return _compareValues(
            _parseLeadingDouble(a.memoryUsage),
            _parseLeadingDouble(b.memoryUsage),
            options.ascending,
          );
        case 'name':
        default:
          return _compareStrings(a.name, b.name, options.ascending);
      }
    });
    return filtered;
  }

  Future<List<DockerImage>> queryDockerImages({
    required String serverId,
    required QueryOptions options,
  }) async {
    final cache = await loadCache(serverId);
    final keyword = options.keyword.trim().toLowerCase();
    final items = List<DockerImage>.from(
      cache?.dockerImages ?? const <DockerImage>[],
    );
    final filtered = items.where((item) {
      if (keyword.isEmpty) {
        return true;
      }
      return item.name.toLowerCase().contains(keyword) ||
          item.tag.toLowerCase().contains(keyword) ||
          item.id.toLowerCase().contains(keyword);
    }).toList();
    filtered.sort((a, b) {
      switch (options.sortBy) {
        case 'tag':
          return _compareStrings(a.tag, b.tag, options.ascending);
        case 'size':
          return _compareValues(
            _parseSizeValue(a.size),
            _parseSizeValue(b.size),
            options.ascending,
          );
        case 'created':
          return _compareStrings(a.created, b.created, options.ascending);
        case 'name':
        default:
          return _compareStrings(a.name, b.name, options.ascending);
      }
    });
    return filtered;
  }

  Future<List<FileInfo>> queryFiles({
    required String serverId,
    required QueryOptions options,
  }) async {
    final cache = await loadCache(serverId);
    final keyword = options.keyword.trim().toLowerCase();
    final items = List<FileInfo>.from(cache?.files ?? const <FileInfo>[]);
    final filtered = items.where((item) {
      if (keyword.isEmpty) {
        return true;
      }
      return item.name.toLowerCase().contains(keyword) ||
          item.modified.toLowerCase().contains(keyword) ||
          item.permissions.toLowerCase().contains(keyword) ||
          item.size.toLowerCase().contains(keyword);
    }).toList();
    filtered.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      switch (options.sortBy) {
        case 'type':
          return _compareStrings(
            a.isDirectory ? 'directory' : 'file',
            b.isDirectory ? 'directory' : 'file',
            options.ascending,
          );
        case 'size':
          return _compareValues(
            _parseSizeValue(a.size),
            _parseSizeValue(b.size),
            options.ascending,
          );
        case 'modified':
          return _compareStrings(a.modified, b.modified, options.ascending);
        case 'permissions':
          return _compareStrings(
            a.permissions,
            b.permissions,
            options.ascending,
          );
        case 'name':
        default:
          return _compareStrings(a.name, b.name, options.ascending);
      }
    });
    return filtered;
  }

  Future<List<FirewallRule>> queryFirewallRules({
    required String serverId,
    required QueryOptions options,
  }) async {
    final cache = await loadCache(serverId);
    final keyword = options.keyword.trim().toLowerCase();
    final items = List<FirewallRule>.from(
      cache?.firewallRules ?? const <FirewallRule>[],
    );
    final filtered = items.where((item) {
      if (keyword.isEmpty) {
        return true;
      }
      return item.id.toLowerCase().contains(keyword) ||
          item.action.toLowerCase().contains(keyword) ||
          item.protocol.toLowerCase().contains(keyword) ||
          (item.port ?? '').toLowerCase().contains(keyword) ||
          (item.source ?? '').toLowerCase().contains(keyword) ||
          (item.destination ?? '').toLowerCase().contains(keyword);
    }).toList();
    filtered.sort((a, b) {
      switch (options.sortBy) {
        case 'action':
          return _compareStrings(a.action, b.action, options.ascending);
        case 'protocol':
          return _compareStrings(a.protocol, b.protocol, options.ascending);
        case 'port':
          return _compareValues(
            _parseInt(a.port),
            _parseInt(b.port),
            options.ascending,
          );
        case 'source':
          return _compareStrings(a.source ?? '', b.source ?? '', options.ascending);
        case 'destination':
          return _compareStrings(
            a.destination ?? '',
            b.destination ?? '',
            options.ascending,
          );
        case 'id':
        default:
          return _compareValues(
            _parseInt(a.id),
            _parseInt(b.id),
            options.ascending,
          );
      }
    });
    return filtered;
  }

  Future<List<Server>> queryServers({
    required QueryOptions options,
  }) async {
    final keyword = options.keyword.trim().toLowerCase();
    final group = options.filters['group'] ?? '全部';
    final items = await loadServers();
    final filtered = items.where((item) {
      final matchesKeyword = keyword.isEmpty ||
          item.name.toLowerCase().contains(keyword) ||
          item.ip.toLowerCase().contains(keyword) ||
          item.group.toLowerCase().contains(keyword) ||
          item.username.toLowerCase().contains(keyword);
      final matchesGroup = group == '全部' || item.group == group;
      return matchesKeyword && matchesGroup;
    }).toList();
    filtered.sort((a, b) {
      switch (options.sortBy) {
        case 'ip':
          return _compareStrings(a.ip, b.ip, options.ascending);
        case 'port':
          return _compareValues(a.port, b.port, options.ascending);
        case 'group':
          return _compareStrings(a.group, b.group, options.ascending);
        case 'status':
          return _compareValues(
            a.isOnline ? 1 : 0,
            b.isOnline ? 1 : 0,
            options.ascending,
          );
        case 'name':
        default:
          return _compareStrings(a.name, b.name, options.ascending);
      }
    });
    return filtered;
  }

  int _compareStrings(String a, String b, bool ascending) {
    final result = a.toLowerCase().compareTo(b.toLowerCase());
    return ascending ? result : -result;
  }

  int _compareValues(num a, num b, bool ascending) {
    final result = a.compareTo(b);
    return ascending ? result : -result;
  }

  int _parseInt(String? value) {
    return int.tryParse((value ?? '').trim()) ?? 0;
  }

  double _parseLeadingDouble(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 0;
    }
    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(value);
    return double.tryParse(match?.group(0) ?? '') ?? 0;
  }

  double _parseSizeValue(String? value) {
    if (value == null || value.trim().isEmpty || value == '-') {
      return 0;
    }
    final raw = value.trim().toUpperCase().replaceAll('IB', 'B');
    final match = RegExp(r'([-+]?\d*\.?\d+)\s*([KMGTP]?B)?').firstMatch(raw);
    final number = double.tryParse(match?.group(1) ?? '') ?? 0;
    final unit = match?.group(2) ?? 'B';
    const scale = <String, double>{
      'B': 1,
      'KB': 1024,
      'MB': 1024 * 1024,
      'GB': 1024 * 1024 * 1024,
      'TB': 1024 * 1024 * 1024 * 1024,
      'PB': 1024 * 1024 * 1024 * 1024 * 1024,
    };
    return number * (scale[unit] ?? 1);
  }

  List<Map<String, Object?>> _extractImportEntries(Object? decoded) {
    if (decoded is List) {
      return decoded.whereType<Map>().map((item) {
        return Map<String, Object?>.from(item.cast<String, Object?>());
      }).toList();
    }
    if (decoded is Map<String, dynamic>) {
      final servers = decoded['servers'];
      if (servers is List) {
        return servers.whereType<Map>().map((item) {
          return Map<String, Object?>.from(item.cast<String, Object?>());
        }).toList();
      }
    }
    throw const FormatException('JSON 格式不正确，未找到 servers 列表');
  }

  Server? _normalizeImportEntry(Map<String, Object?> jsonMap) {
    final name = jsonMap['name']?.toString().trim() ?? '';
    final ip = jsonMap['ip']?.toString().trim() ?? '';
    final username = jsonMap['username']?.toString().trim() ?? '';
    final password = jsonMap['password']?.toString() ?? '';
    final privateKey = jsonMap['privateKey']?.toString() ??
        jsonMap['private_key']?.toString();
    final group = jsonMap['group']?.toString().trim() ?? _defaultGroup;
    final port = int.tryParse(jsonMap['port']?.toString() ?? '');
    final rawTags = jsonMap['tags'];
    final tags = rawTags is List
        ? rawTags.map((item) => item.toString()).where((item) => item.isNotEmpty).toList()
        : const <String>[];

    if (ip.isEmpty || username.isEmpty || port == null || port <= 0 || port > 65535) {
      return null;
    }

    return Server(
      id: jsonMap['id']?.toString() ?? '',
      name: name.isEmpty ? ip : name,
      ip: ip,
      port: port,
      username: username,
      password: password,
      privateKey: privateKey == null || privateKey.trim().isEmpty
          ? null
          : privateKey.trim(),
      group: group.isEmpty ? _defaultGroup : group,
      tags: tags,
      isOnline: false,
    );
  }

  Map<String, Object?> _serverToExportJson(Server server) {
    return {
      'name': server.name,
      'ip': server.ip,
      'port': server.port,
      'username': server.username,
      'password': server.password,
      'privateKey': server.privateKey,
      'group': server.group,
      'tags': server.tags,
    };
  }

  String _serverIdentityKey(Server server) {
    return '${_normalizeIp(server.ip)}|${server.port}|${server.username.trim().toLowerCase()}';
  }

  String _normalizeIp(String value) {
    return value.trim().toLowerCase();
  }

  String _buildImportedServerName({
    required String baseName,
    required String ip,
    required Set<String> existingNames,
  }) {
    final normalizedBase = baseName.trim().isEmpty ? ip : baseName.trim();
    final safeIp = ip.trim().isEmpty ? '导入' : ip.trim();
    var candidate = '$normalizedBase (导入:$safeIp)';
    var index = 2;
    while (existingNames.contains(candidate)) {
      candidate = '$normalizedBase (导入:$safeIp-$index)';
      index++;
    }
    return candidate;
  }

  String _generateImportedServerId(int sequence) {
    return 'import_${DateTime.now().microsecondsSinceEpoch}_$sequence';
  }

  Map<String, Object?> _serverToRow(Server server) {
    return {
      'id': server.id,
      'name': server.name,
      'ip': server.ip,
      'port': server.port,
      'username': server.username,
      'password': server.password,
      'private_key': server.privateKey,
      'group_name': server.group,
      'tags_json': json.encode(server.tags),
      'is_online': server.isOnline ? 1 : 0,
      'os_info': server.osInfo,
      'kernel_version': server.kernelVersion,
      'uptime': server.uptime,
    };
  }

  Server _serverFromRow(Map<String, Object?> row) {
    return Server(
      id: row['id']! as String,
      name: row['name']! as String,
      ip: row['ip']! as String,
      port: row['port']! as int,
      username: row['username']! as String,
      password: row['password']! as String,
      privateKey: row['private_key'] as String?,
      group: (row['group_name'] as String?) ?? _defaultGroup,
      tags: List<String>.from(
        json.decode((row['tags_json'] as String?) ?? '[]') as List<dynamic>,
      ),
      isOnline: ((row['is_online'] as int?) ?? 0) == 1,
      osInfo: row['os_info'] as String?,
      kernelVersion: row['kernel_version'] as String?,
      uptime: row['uptime'] as String?,
    );
  }
}
