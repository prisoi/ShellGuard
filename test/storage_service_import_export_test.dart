import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shellguard_free/models/server.dart';
import 'package:shellguard_free/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory originalDirectory;
  late Directory tempDirectory;
  StorageService? storage;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    originalDirectory = Directory.current;
    tempDirectory = await Directory.systemTemp.createTemp(
      'shellguard-storage-test-',
    );
    Directory.current = tempDirectory;
    storage = StorageService();
  });

  tearDown(() async {
    await storage?.close();
    Directory.current = originalDirectory;
    if (await tempDirectory.exists()) {
      try {
        await tempDirectory.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('imports JSON without overwriting local configs and renames IP conflicts', () async {
    final currentStorage = storage!;
    await currentStorage.saveServers([
      Server(
        id: 'local-1',
        name: '生产机',
        ip: '10.0.0.8',
        port: 22,
        username: 'root',
        password: 'secret',
        group: '生产环境',
      ),
    ]);

    final importFile = File('${tempDirectory.path}\\import.json');
    await importFile.writeAsString(
      jsonEncode({
        'servers': [
          {
            'name': '生产机-重复',
            'ip': '10.0.0.8',
            'port': 22,
            'username': 'root',
            'password': 'secret',
            'group': '生产环境',
          },
          {
            'name': '生产机',
            'ip': '10.0.0.8',
            'port': 22,
            'username': 'admin',
            'password': 'secret2',
            'group': '测试环境',
          },
          {
            'name': '测试机',
            'ip': '10.0.0.9',
            'port': 2222,
            'username': 'ubuntu',
            'password': 'secret3',
            'group': '测试环境',
          },
        ],
      }),
    );

    final result = await currentStorage.importServersFromJson(
      filePath: importFile.path,
      maxAdditionalServers: 5,
    );

    expect(result.importedCount, 2);
    expect(result.duplicateSkippedCount, 1);
    expect(result.renamedCount, 1);

    final servers = await currentStorage.loadServers();
    expect(servers.length, 3);
    expect(
      servers.any((server) => server.name == '测试机' && server.ip == '10.0.0.9'),
      isTrue,
    );
    expect(
      servers.any(
        (server) =>
            server.ip == '10.0.0.8' &&
            server.username == 'admin' &&
            server.name.contains('(导入:10.0.0.8)'),
      ),
      isTrue,
    );
    expect(
      servers.where((server) => server.ip == '10.0.0.8' && server.username == 'root').length,
      1,
    );
  });

  test('exports server list as JSON payload', () async {
    final currentStorage = storage!;
    final servers = [
      Server(
        id: 'export-1',
        name: '导出机',
        ip: '192.168.0.10',
        port: 22,
        username: 'root',
        password: 'secret',
      ),
    ];

    final targetPath = '${tempDirectory.path}\\servers.json';
    final result = await currentStorage.exportServersToJson(
      servers: servers,
      targetPath: targetPath,
    );

    expect(result.exportedCount, 1);
    final payload = jsonDecode(await File(targetPath).readAsString()) as Map<String, dynamic>;
    expect(payload['schema'], 'shellguard_server_list');
    expect(payload['serverCount'], 1);
    expect((payload['servers'] as List).first['ip'], '192.168.0.10');
  });
}
