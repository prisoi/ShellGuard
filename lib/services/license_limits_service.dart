import 'dart:async';

class RuntimeLicenseLimits {
  final int maxManagedServers;
  final int maxConcurrentAccessTokens;
  final Duration maxAccessTokenLifetime;

  const RuntimeLicenseLimits({
    required this.maxManagedServers,
    required this.maxConcurrentAccessTokens,
    required this.maxAccessTokenLifetime,
  });

  static const RuntimeLicenseLimits free = RuntimeLicenseLimits(
    maxManagedServers: 5,
    maxConcurrentAccessTokens: 2,
    maxAccessTokenLifetime: Duration(hours: 24),
  );
}

class LicenseLimitsService {
  const LicenseLimitsService();

  Future<RuntimeLicenseLimits> loadRuntimeLimits() async {
    try {
      final licensed = await _loadLicensedLimits();
      if (licensed != null) {
        return licensed;
      }
    } catch (_) {}
    return RuntimeLicenseLimits.free;
  }

  Future<RuntimeLicenseLimits?> _loadLicensedLimits() async {
    return null;
  }
}
