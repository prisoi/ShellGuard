import 'refresh_scope.dart';

class RefreshPolicy {
  const RefreshPolicy();

  Duration resolveMinInterval({
    required RefreshScope scope,
    required int usageScore,
    required bool? dockerInstalled,
  }) {
    switch (scope) {
      case RefreshScope.dashboard:
        return const Duration(seconds: 5);
      case RefreshScope.firewall:
      case RefreshScope.docker:
      case RefreshScope.ports:
      case RefreshScope.processes:
      case RefreshScope.services:
      case RefreshScope.files:
        return const Duration(seconds: 5);
    }
  }
}
