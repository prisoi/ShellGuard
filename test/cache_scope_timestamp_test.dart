import 'package:flutter_test/flutter_test.dart';
import 'package:shellguard_free/models/cache_data.dart';

void main() {
  test('CacheData 保留按模块更新时间并可序列化', () {
    final cache = CacheData(
      serverId: 'server-1',
      timestamp: DateTime.parse('2026-07-23T10:00:00Z'),
      scopeUpdatedAt: const {
        'dashboard': '2026-07-23T10:00:00Z',
        'docker': '2026-07-23T10:05:00Z',
      },
    );

    final json = cache.toJson();
    final restored = CacheData.fromJson(json);

    expect(restored.scopeUpdatedAt['dashboard'], '2026-07-23T10:00:00Z');
    expect(restored.scopeUpdatedAt['docker'], '2026-07-23T10:05:00Z');
  });
}

