import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/refresh_scope.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import '../widgets/app_button_styles.dart';

class DashboardScreen extends StatefulWidget {
  final ValueChanged<String>? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  ResourceUsage? _resourceUsage;
  SystemInfo? _systemInfo;
  bool _isRefreshing = false;
  String? _lastServerId;
  String? _lastUpdatedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromCache();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<AppProvider>(context);
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.dashboard.key];
    if (_lastServerId != provider.selectedServer?.id) {
      _lastServerId = provider.selectedServer?.id;
      _lastUpdatedAt = null;
      _syncFromCache();
      provider.onPageEnter(RefreshScope.dashboard);
    } else if (updatedAt != null && updatedAt != _lastUpdatedAt) {
      _syncFromCache();
    }
  }

  void _syncFromCache() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.currentCache != null) {
      setState(() {
        _resourceUsage = provider.currentCache!.resourceUsage;
        _systemInfo = provider.currentCache!.systemInfo;
        _lastUpdatedAt =
            provider.currentCache!.scopeUpdatedAt[RefreshScope.dashboard.key];
      });
    } else {
      setState(() {
        _resourceUsage = null;
        _systemInfo = null;
        _lastUpdatedAt = null;
      });
    }
  }

  Future<void> refresh() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    setState(() => _isRefreshing = true);
    await provider.requestRefreshNow(
      RefreshScope.dashboard,
      reason: 'dashboard-refresh',
    );
    _syncFromCache();
    setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFFf0f4f8),
      child: ListView(
        children: [
          _buildSystemInfoBar(provider),
          const SizedBox(height: 20),
          _buildStatCards(provider),
          const SizedBox(height: 20),
          _buildCharts(),
          const SizedBox(height: 20),
          _buildBottomSection(),
        ],
      ),
    );
  }

  Widget _buildSystemInfoBar(AppProvider provider) {
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.dashboard.key];
    final primaryGpu = _resourceUsage?.primaryGpu;
    return Container(
      height: 40,
      color: const Color(0xFFf8fafc),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              '当前服务器: ${provider.selectedServer?.ip ?? '未选择'}',
              style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
            ),
            const SizedBox(width: 20),
            Text(
              '系统: ${_systemInfo?.osDisplayLabel ?? provider.selectedServer?.osDisplayLabel ?? '未知'}',
              style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
            ),
            if ((_systemInfo?.packageManager.isNotEmpty ?? false) ||
                (provider.selectedServer?.packageManager?.isNotEmpty ?? false)) ...[
              const SizedBox(width: 20),
              Text(
                '包管理: ${_systemInfo?.packageManager.isNotEmpty == true ? _systemInfo!.packageManager : provider.selectedServer?.packageManager ?? '未知'}',
                style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
              ),
            ],
            const SizedBox(width: 20),
            Text(
              '更新时间: ${updatedAt == null ? '暂无' : _formatTimestamp(updatedAt)}',
              style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
            ),
            const SizedBox(width: 20),
            Text(
              '内核: ${_systemInfo?.kernelVersion ?? '未知'}',
              style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
            ),
            const SizedBox(width: 20),
            Text(
              '运行: ${_systemInfo?.uptime ?? '未知'}',
              style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
            ),
            const SizedBox(width: 20),
            Text(
              'CPU: ${_systemInfo?.cpuCores ?? 0}核',
              style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
            ),
            const SizedBox(width: 20),
            Text(
              '内存: ${_systemInfo?.memoryTotal ?? '未知'}',
              style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
            ),
            const SizedBox(width: 20),
            Text(
              '磁盘: ${_systemInfo?.diskTotal ?? '未知'}',
              style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
            ),
            if (primaryGpu != null) ...[
              const SizedBox(width: 20),
              Text(
                'GPU: ${primaryGpu.name}',
                style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCards(AppProvider provider) {
    if (_isRefreshing && _resourceUsage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final cards = <Widget>[
      _buildStatCard(
        'CPU 使用率',
        '${_resourceUsage?.cpuUsage.toStringAsFixed(1) ?? '0'}%',
        const Color(0xFF2563eb),
        Icons.memory,
        progress: (_resourceUsage?.cpuUsage ?? 0) / 100,
      ),
      _buildStatCard(
        '内存占用',
        _resourceUsage?.memoryUsed ?? '0',
        const Color(0xFF10b981),
        Icons.storage,
        subText: '/ ${_resourceUsage?.memoryTotal ?? '0'}',
        progress: (_resourceUsage?.memoryPercent ?? 0) / 100,
      ),
      _buildStatCard(
        '磁盘使用',
        _resourceUsage?.diskUsed ?? '0',
        const Color(0xFFf59e0b),
        Icons.storage,
        subText: '/ ${_resourceUsage?.diskTotal ?? '0'}',
        progress: (_resourceUsage?.diskPercent ?? 0) / 100,
      ),
      _buildStatCard(
        '网络流量',
        '↑ ${_resourceUsage?.networkUpload ?? '0'}',
        const Color(0xFF1a2332),
        Icons.network_check,
        subText: '↓ ${_resourceUsage?.networkDownload ?? '0'}',
      ),
    ];
    final primaryGpu = _resourceUsage?.primaryGpu;
    if (primaryGpu != null) {
      cards.add(
        _buildStatCard(
          '${primaryGpu.vendor.toUpperCase()} GPU',
          primaryGpu.memoryUsed,
          const Color(0xFF7C3AED),
          Icons.view_in_ar,
          subText: '/ ${primaryGpu.memoryTotal} · 核心 ${primaryGpu.utilizationPercent.toStringAsFixed(0)}%',
          progress: primaryGpu.memoryPercent / 100,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1280
            ? 4
            : width >= 900
                ? 3
                : width >= 620
                    ? 2
                    : 1;
        final ratio = crossAxisCount == 1 ? 2.4 : 1.5;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: ratio,
          children: cards,
        );
      },
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    IconData icon, {
    String? subText,
    double? progress,
  }) {
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
          Text(
            title,
            style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, color: color.withValues(alpha: 0.5), size: 20),
            ],
          ),
          if (subText != null)
            Text(
              subText,
              style: const TextStyle(color: Color(0xFF6b7c93), fontSize: 11),
            ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            AppProgressBar(value: progress, color: color, height: 4, radius: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildCharts() {
    return Row(
      children: [
        Expanded(child: _buildCpuChart()),
        const SizedBox(width: 16),
        Expanded(child: _buildMemoryChart()),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CPU 负载趋势 (最近1小时)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1a2332),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true),
                titlesData: const FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 59,
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      60,
                      (i) => FlSpot(i.toDouble(), (10 + i % 30).toDouble()),
                    ),
                    isCurved: true,
                    color: const Color(0xFF2563eb),
                    barWidth: 2,
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF2563eb).withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '内存使用分布',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1a2332),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    value: _resourceUsage?.memoryPercent ?? 50,
                    color: const Color(0xFF10b981),
                    title: '已用',
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 11),
                  ),
                  PieChartSectionData(
                    value: 20,
                    color: const Color(0xFFf59e0b),
                    title: '缓存',
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 11),
                  ),
                  PieChartSectionData(
                    value: 30,
                    color: const Color(0xFFe2e8f0),
                    title: '空闲',
                    radius: 50,
                    titleStyle: const TextStyle(fontSize: 11),
                  ),
                ],
                centerSpaceRadius: 20,
                sectionsSpace: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Row(
      children: [
        Expanded(child: _buildDiskPartitions()),
        const SizedBox(width: 16),
        Expanded(child: _buildQuickActions()),
      ],
    );
  }

  Widget _buildDiskPartitions() {
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
            '磁盘分区详情',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1a2332),
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              _buildDiskBar('/ 分区', _resourceUsage?.diskPercent ?? 0),
              const SizedBox(height: 8),
              _buildDiskBar('/ 已用', _resourceUsage?.diskPercent ?? 0),
              const SizedBox(height: 8),
              _buildDiskBar('/ 可用', 100 - (_resourceUsage?.diskPercent ?? 0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiskBar(String name, double percent) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6b7c93)),
            ),
            Text(
              '$percent%',
              style: const TextStyle(fontSize: 11, color: Color(0xFF1a2332)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AppProgressBar(
          value: percent / 100,
          color: percent > 80
              ? const Color(0xFFef4444)
              : const Color(0xFF2563eb),
          height: 6,
          radius: 3,
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
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
            '快捷运维入口',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1a2332),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.2,
            children: [
              _buildQuickAction('系统更新', Icons.system_update, 'tools'),
              _buildQuickAction('防火墙', Icons.shield, 'firewall'),
              _buildQuickAction('进程', Icons.list_alt, 'processes'),
              _buildQuickAction(
                'Docker',
                Icons.integration_instructions,
                'docker',
              ),
              _buildQuickAction('终端', Icons.terminal, 'terminal'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(String label, IconData icon, String screen) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onNavigate?.call(screen),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFeff6ff),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFbfdbfe)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF1d4ed8), size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF1d4ed8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
