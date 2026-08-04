import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/refresh_scope.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => MonitoringScreenState();
}

class MonitoringScreenState extends State<MonitoringScreen> {
  final List<double> _cpuHistory = [];
  final List<double> _memoryHistory = [];
  final List<double> _diskHistory = [];
  final List<double> _gpuMemoryHistory = [];
  bool _isLoading = false;
  Timer? _refreshTimer;
  String? _lastServerId;
  String? _lastUpdatedAt;
  ResourceUsage? _resourceUsage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      _applyCache(provider);
      provider.onPageEnter(RefreshScope.dashboard);
    });
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<AppProvider>(context);
    final serverId = provider.selectedServer?.id;
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.dashboard.key];
    if (_lastServerId != serverId) {
      _lastServerId = serverId;
      _cpuHistory.clear();
      _memoryHistory.clear();
      _diskHistory.clear();
      _gpuMemoryHistory.clear();
      _lastUpdatedAt = null;
      _applyCache(provider);
      provider.onPageEnter(RefreshScope.dashboard);
    } else if (updatedAt != null && updatedAt != _lastUpdatedAt) {
      _applyCache(provider);
    }
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) {
        return;
      }
      final provider = Provider.of<AppProvider>(context, listen: false);
      await provider.reloadSelectedServerCache(notify: false);
      if (!mounted) {
        return;
      }
      _applyCache(provider);
      await provider.requestRefreshIfStale(
        RefreshScope.dashboard,
        reason: 'monitoring-poll',
      );
    });
  }

  void _applyCache(AppProvider provider) {
    final cache = provider.currentCache;
    final usage = cache?.resourceUsage;
    final updatedAt = cache?.scopeUpdatedAt[RefreshScope.dashboard.key];

    if (usage == null) {
      setState(() {
        _resourceUsage = null;
        _lastUpdatedAt = updatedAt;
      });
      return;
    }

    final shouldAppend = updatedAt != null && updatedAt != _lastUpdatedAt;
    setState(() {
      _resourceUsage = usage;
      if (shouldAppend) {
        _cpuHistory.add(usage.cpuUsage);
        _memoryHistory.add(usage.memoryPercent);
        _diskHistory.add(usage.diskPercent);
        _gpuMemoryHistory.add(usage.primaryGpu?.memoryPercent ?? 0);
        if (_cpuHistory.length > 30) {
          _cpuHistory.removeAt(0);
          _memoryHistory.removeAt(0);
          _diskHistory.removeAt(0);
          _gpuMemoryHistory.removeAt(0);
        }
      } else if (_cpuHistory.isEmpty) {
        _cpuHistory.add(usage.cpuUsage);
        _memoryHistory.add(usage.memoryPercent);
        _diskHistory.add(usage.diskPercent);
        _gpuMemoryHistory.add(usage.primaryGpu?.memoryPercent ?? 0);
      }
      _lastUpdatedAt = updatedAt;
    });
  }

  Future<void> refresh() async {
    _cpuHistory.clear();
    _memoryHistory.clear();
    _diskHistory.clear();
    _gpuMemoryHistory.clear();
    final provider = Provider.of<AppProvider>(context, listen: false);
    setState(() => _isLoading = true);
    await provider.requestRefreshNow(
      RefreshScope.dashboard,
      reason: 'monitoring-refresh',
    );
    await provider.reloadSelectedServerCache(notify: false);
    if (!mounted) {
      return;
    }
    _applyCache(provider);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFFf0f4f8),
      child: Column(
        children: [
          _buildTopBar(provider),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 980 ? 2 : 1;
                final cards = <Widget>[
                  _buildCpuChart(),
                  _buildMemoryChart(),
                  _buildDiskChart(),
                  _buildNetworkInfo(),
                ];
                if (_resourceUsage?.hasGpu ?? false) {
                  cards.add(_buildGpuInfoCard());
                }
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: crossAxisCount == 1 ? 2.3 : 1.35,
                  children: cards,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(AppProvider provider) {
    final primaryGpu = _resourceUsage?.primaryGpu;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          '实时资源监控',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (_isLoading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        Text(
          _cpuHistory.isNotEmpty
              ? 'CPU: ${_cpuHistory.last.toStringAsFixed(1)}%'
              : 'CPU: --',
          style: const TextStyle(fontSize: 13),
        ),
        Text(
          _memoryHistory.isNotEmpty
              ? '内存: ${_memoryHistory.last.toStringAsFixed(1)}%'
              : '内存: --',
          style: const TextStyle(fontSize: 13),
        ),
        if (primaryGpu != null)
          Text(
            'GPU显存: ${primaryGpu.memoryPercent.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 13),
          ),
        if (provider.selectedServer != null)
          Text(
            '系统: ${provider.selectedServer!.osDisplayLabel}',
            style: const TextStyle(fontSize: 13),
          ),
        Text(
          _lastUpdatedAt == null
              ? '等待后台采集'
              : '更新于 ${_formatTimestamp(_lastUpdatedAt!)}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
        ),
      ],
    );
  }

  Widget _buildCpuChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        children: [
          const Text(
            'CPU 使用情况',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: _cpuHistory.length.toDouble(),
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: _cpuHistory.asMap().entries.map((entry) {
                      return FlSpot(entry.key.toDouble(), entry.value);
                    }).toList(),
                    isCurved: true,
                    color: const Color(0xFF2563eb),
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF2563eb).withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 12, height: 4, color: const Color(0xFF2563eb)),
              const SizedBox(width: 8),
              Text(
                _cpuHistory.isNotEmpty
                    ? '${_cpuHistory.last.toStringAsFixed(1)}%'
                    : '--',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        children: [
          const Text(
            '内存使用情况',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: _memoryHistory.length.toDouble(),
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: _memoryHistory.asMap().entries.map((entry) {
                      return FlSpot(entry.key.toDouble(), entry.value);
                    }).toList(),
                    isCurved: true,
                    color: const Color(0xFF10b981),
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF10b981).withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 12, height: 4, color: const Color(0xFF10b981)),
              const SizedBox(width: 8),
              Text(
                _memoryHistory.isNotEmpty
                    ? '${_memoryHistory.last.toStringAsFixed(1)}%'
                    : '--',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiskChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        children: [
          const Text(
            '磁盘使用情况',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: _diskHistory.length.toDouble(),
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: _diskHistory.asMap().entries.map((entry) {
                      return FlSpot(entry.key.toDouble(), entry.value);
                    }).toList(),
                    isCurved: true,
                    color: const Color(0xFFf59e0b),
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFf59e0b).withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 12, height: 4, color: const Color(0xFFf59e0b)),
              const SizedBox(width: 8),
              Text(
                _diskHistory.isNotEmpty
                    ? '${_diskHistory.last.toStringAsFixed(1)}%'
                    : '--',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkInfo() {
    final upload = _resourceUsage?.networkUpload ?? '--';
    final download = _resourceUsage?.networkDownload ?? '--';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        children: [
          const Text(
            '网络流量',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              color: const Color(0xFFf0f4f8),
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.network_check,
                    size: 48,
                    color: Color(0xFF2563eb),
                  ),
                  const SizedBox(height: 12),
                  Text('上传累计: $upload', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('下载累计: $download', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpuInfoCard() {
    final devices = _resourceUsage?.gpuDevices ?? const <GpuDeviceUsage>[];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GPU 状态',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: devices.isEmpty
                ? const Center(
                    child: Text(
                      '未检测到 GPU',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
                    ),
                  )
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final gpu = devices[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${gpu.vendor.toUpperCase()} #${gpu.index} ${gpu.name}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '核心负载 ${gpu.utilizationPercent.toStringAsFixed(1)}%'
                              '${gpu.temperature == null ? '' : ' · ${gpu.temperature}'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '显存 ${gpu.memoryUsed} / ${gpu.memoryTotal}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: (gpu.memoryPercent / 100).clamp(0.0, 1.0),
                              backgroundColor: const Color(0xFFE2E8F0),
                              color: const Color(0xFF7C3AED),
                              minHeight: 6,
                            ),
                            if (gpu.note != null && gpu.note!.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                gpu.note!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String raw) {
    final time = DateTime.tryParse(raw);
    if (time == null) {
      return raw;
    }
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
