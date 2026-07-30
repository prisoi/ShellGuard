import 'package:flutter_test/flutter_test.dart';
import 'package:shellguard_free/core/refresh_policy.dart';
import 'package:shellguard_free/core/refresh_scope.dart';

void main() {
  test('高频 dashboard 维持较短刷新间隔', () {
    const policy = RefreshPolicy();
    final interval = policy.resolveMinInterval(
      scope: RefreshScope.dashboard,
      usageScore: 100,
      dockerInstalled: true,
    );

    expect(interval, const Duration(seconds: 30));
  });

  test('未安装 docker 的服务器自动降频到按天', () {
    const policy = RefreshPolicy();
    final interval = policy.resolveMinInterval(
      scope: RefreshScope.docker,
      usageScore: 100,
      dockerInstalled: false,
    );

    expect(interval, const Duration(hours: 24));
  });
}

