import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_provider.dart';
import 'app_button_styles.dart';

class Sidebar extends StatelessWidget {
  final String currentScreen;
  final Function(String) onNavigate;

  const Sidebar({
    super.key,
    required this.currentScreen,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Container(
      width: 240,
      color: const Color(0xFF1a2332),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildNavigation(context),
                    const SizedBox(height: 20),
                    _buildUpgradeBanner(),
                    const SizedBox(height: 20),
                    _buildServerQuota(provider),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2d3a4f))),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security, color: Color(0xFF2563eb), size: 32),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ShellGuard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '壳御 · 免费版',
                    style: TextStyle(color: Color(0xFF6b7c93), fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavigation(BuildContext context) {
    final navItems = [
      {'icon': Icons.dashboard, 'label': '仪表盘', 'screen': 'dashboard'},
      {'icon': Icons.computer, 'label': '资产管理', 'screen': 'assets'},
      {'icon': Icons.auto_awesome, 'label': 'AI助力', 'screen': 'ai_assistant'},
      {'icon': Icons.build, 'label': '工具安装', 'screen': 'tools'},
      {'icon': Icons.shield, 'label': '防火墙', 'screen': 'firewall'},
      {'icon': Icons.usb, 'label': '端口管理', 'screen': 'ports'},
      {'icon': Icons.list_alt, 'label': '进程管理', 'screen': 'processes'},
      {'icon': Icons.settings, 'label': '服务管理', 'screen': 'services'},
      {
        'icon': Icons.integration_instructions,
        'label': 'Docker',
        'screen': 'docker',
      },
      {'icon': Icons.show_chart, 'label': '资源监控', 'screen': 'monitoring'},
      {'icon': Icons.folder, 'label': '文件管理', 'screen': 'files'},
      {'icon': Icons.terminal, 'label': 'Web终端', 'screen': 'terminal'},
      {'icon': Icons.hub, 'label': '远程控制', 'screen': 'remote_control'},
      {'icon': Icons.settings_applications, 'label': '系统设置', 'screen': 'settings'},
    ];

    return Column(
      children: navItems.map((item) {
        final screen = item['screen'] as String;
        final isSelected = currentScreen == screen;
        return GestureDetector(
          onTap: () => onNavigate(screen),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF2563eb) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  item['icon'] as IconData,
                  color: isSelected ? Colors.white : const Color(0xFF6b7c93),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(
                  item['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF6b7c93),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUpgradeBanner() {
    return InkWell(
      onTap: _openProfessionalEditionPage,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2563eb).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '专业版',
              style: TextStyle(
                color: Color(0xFF60a5fa),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '解锁无限资产，运维便捷又安全',
              style: TextStyle(color: Color(0xFF6b7c93), fontSize: 10),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2563eb).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '升级 →',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProfessionalEditionPage() async {
    final uri = Uri.parse('https://shellguard.cn');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildServerQuota(AppProvider provider) {
    final used = provider.servers.length;
    final total = 10;
    final percentage = (used / total) * 100;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2d3a4f))),
      ),
      child: Column(
        children: [
          Text(
            '服务器 $used/$total',
            style: const TextStyle(color: Color(0xFF4a5568), fontSize: 11),
          ),
          const SizedBox(height: 4),
          AppProgressBar(
            value: percentage / 100,
            color: const Color(0xFF2563eb),
            height: 4,
            radius: 2,
            backgroundColor: const Color(0xFF2d3a4f),
          ),
        ],
      ),
    );
  }
}
