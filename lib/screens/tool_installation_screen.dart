import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import '../widgets/app_button_styles.dart';

class ToolInstallationScreen extends StatefulWidget {
  const ToolInstallationScreen({super.key});

  @override
  State<ToolInstallationScreen> createState() => _ToolInstallationScreenState();
}

class _ToolInstallationScreenState extends State<ToolInstallationScreen> {
  List<ToolInfo> _tools = [];
  final List<String> _selectedTools = [];
  String _searchText = '';
  String _selectedCategory = '全部';
  String _sortBy = 'name';
  bool _sortAscending = true;
  bool _isInstalling = false;

  @override
  void initState() {
    super.initState();
    _loadTools();
  }

  void _loadTools() {
    _tools = [
      ToolInfo(
        name: 'nmap',
        category: '网络工具',
        description: '网络扫描与端口探测工具',
        command: 'apt install nmap',
      ),
      ToolInfo(
        name: 'net-tools',
        category: '网络工具',
        description: 'ifconfig/netstat 等经典工具',
        command: 'apt install net-tools',
      ),
      ToolInfo(
        name: 'curl',
        category: '开发工具',
        description: '命令行 URL 传输工具',
        command: 'apt install curl',
      ),
      ToolInfo(
        name: 'tcpdump',
        category: '网络工具',
        description: '网络数据包抓取分析',
        command: 'apt install tcpdump',
      ),
      ToolInfo(
        name: 'iftop',
        category: '网络工具',
        description: '实时网络流量监控',
        command: 'apt install iftop',
      ),
      ToolInfo(
        name: 'nethogs',
        category: '网络工具',
        description: '按进程统计网络带宽',
        command: 'apt install nethogs',
      ),
      ToolInfo(
        name: 'iproute2',
        category: '网络工具',
        description: '高级网络配置工具',
        command: 'apt install iproute2',
      ),
      ToolInfo(
        name: 'traceroute',
        category: '网络工具',
        description: '路由追踪工具',
        command: 'apt install traceroute',
      ),
      ToolInfo(
        name: 'dig',
        category: '网络工具',
        description: 'DNS 查询工具',
        command: 'apt install dnsutils',
      ),
      ToolInfo(
        name: 'nc',
        category: '网络工具',
        description: 'netcat 网络工具',
        command: 'apt install netcat-openbsd',
      ),
      ToolInfo(
        name: 'htop',
        category: '监控工具',
        description: '交互式进程查看器',
        command: 'apt install htop',
      ),
      ToolInfo(
        name: 'glances',
        category: '监控工具',
        description: '系统监控工具',
        command: 'apt install glances',
      ),
      ToolInfo(
        name: 'ripgrep',
        category: '开发工具',
        description: '快速文件搜索工具',
        command: 'apt install ripgrep',
      ),
      ToolInfo(
        name: 'fzf',
        category: '开发工具',
        description: '模糊查找工具',
        command: 'apt install fzf',
      ),
      ToolInfo(
        name: 'tldr',
        category: '开发工具',
        description: '命令行帮助文档',
        command: 'apt install tldr',
      ),
      ToolInfo(
        name: 'git',
        category: '开发工具',
        description: '版本控制工具',
        command: 'apt install git',
      ),
      ToolInfo(
        name: 'vim',
        category: '开发工具',
        description: '文本编辑器',
        command: 'apt install vim',
      ),
      ToolInfo(
        name: 'wget',
        category: '开发工具',
        description: '命令行下载工具',
        command: 'apt install wget',
      ),
      ToolInfo(
        name: 'ufw',
        category: '防火墙',
        description: 'Ubuntu 默认防火墙',
        command: 'apt install ufw',
      ),
      ToolInfo(
        name: 'docker',
        category: 'Docker',
        description: 'Docker 引擎',
        command: 'apt install docker.io',
      ),
      ToolInfo(
        name: 'python3',
        category: '开发工具',
        description: 'Python 3 运行时',
        command: 'apt install python3',
      ),
      ToolInfo(
        name: 'pip',
        category: '开发工具',
        description: 'Python 包管理工具',
        command: 'apt install python3-pip',
      ),
      ToolInfo(
        name: 'nodejs',
        category: '开发工具',
        description: 'Node.js 运行时',
        command: 'apt install nodejs',
      ),
      ToolInfo(
        name: 'ncdu',
        category: '开发工具',
        description: '磁盘使用分析工具',
        command: 'apt install ncdu',
      ),
    ];
  }

  Future<void> _checkInstalledStatus() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isConnected) return;

    for (var i = 0; i < _tools.length; i++) {
      try {
        final installed = await provider.sshManager.checkToolInstalled(
          _tools[i].name,
        );
        setState(() {
          _tools[i] = ToolInfo(
            name: _tools[i].name,
            category: _tools[i].category,
            description: _tools[i].description,
            command: _tools[i].command,
            isInstalled: installed,
          );
        });
      } catch (_) {}
    }
  }

  void _toggleTool(String toolName) {
    setState(() {
      if (_selectedTools.contains(toolName)) {
        _selectedTools.remove(toolName);
      } else {
        _selectedTools.add(toolName);
      }
    });
  }

  Future<void> _installSelectedTools() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isConnected || _selectedTools.isEmpty) return;

    setState(() => _isInstalling = true);

    for (final tool in _selectedTools) {
      try {
        await provider.sshManager.installTool(tool);
        final index = _tools.indexWhere((t) => t.name == tool);
        if (index != -1) {
          setState(() {
            _tools[index] = _tools[index].copyWith(isInstalled: true);
          });
        }
      } catch (_) {}
    }

    setState(() {
      _isInstalling = false;
      _selectedTools.clear();
    });
  }

  List<ToolInfo> get _filteredTools {
    final filtered = _tools.where((tool) {
      final matchesSearch =
          tool.name.toLowerCase().contains(_searchText.toLowerCase()) ||
          tool.description.toLowerCase().contains(_searchText.toLowerCase());
      final matchesCategory =
          _selectedCategory == '全部' || tool.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
    filtered.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'category':
          result = a.category.toLowerCase().compareTo(b.category.toLowerCase());
          break;
        case 'installed':
          result = (a.isInstalled ? 1 : 0).compareTo(b.isInstalled ? 1 : 0);
          break;
        case 'name':
        default:
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
      }
      return _sortAscending ? result : -result;
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final categories = ['全部', '网络工具', '监控工具', '开发工具', '防火墙', 'Docker'];

    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFFf0f4f8),
      child: Column(
        children: [
          _buildTopBar(provider, categories),
          const SizedBox(height: 16),
          Expanded(child: _buildToolGrid()),
          const SizedBox(height: 16),
          if (_selectedTools.isNotEmpty) _buildInstallButton(),
        ],
      ),
    );
  }

  Widget _buildTopBar(AppProvider provider, List<String> categories) {
    return Row(
      children: [
        Expanded(
          child: AppControlShell(
            child: TextField(
              decoration: AppFieldStyles.toolbarInput(hintText: '搜索工具...'),
              onChanged: (text) => setState(() => _searchText = text),
            ),
          ),
        ),
        const SizedBox(width: 16),
        ...categories.map((category) {
          final isSelected = _selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              onPressed: () => setState(() => _selectedCategory = category),
              style: isSelected
                  ? AppButtonStyles.primary(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    )
                  : AppButtonStyles.secondary(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ).copyWith(
                      foregroundColor: const WidgetStatePropertyAll(
                        AppColors.textMuted,
                      ),
                      side: const WidgetStatePropertyAll(
                        BorderSide(color: AppColors.border),
                      ),
                    ),
              child: Text(category, style: const TextStyle(fontSize: 11)),
            ),
          );
        }),
        const SizedBox(width: 8),
        AppControlShell(
          width: 170,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: '$_sortBy:${_sortAscending ? 'asc' : 'desc'}',
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'name:asc', child: Text('名称 A-Z')),
                DropdownMenuItem(value: 'name:desc', child: Text('名称 Z-A')),
                DropdownMenuItem(value: 'category:asc', child: Text('分类升序')),
                DropdownMenuItem(value: 'installed:desc', child: Text('已安装优先')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                final parts = value.split(':');
                setState(() {
                  _sortBy = parts.first;
                  _sortAscending = parts.length > 1 ? parts[1] == 'asc' : true;
                });
              },
            ),
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: provider.isConnected ? _checkInstalledStatus : null,
          style: AppButtonStyles.subtle(),
          child: const Text('刷新状态'),
        ),
      ],
    );
  }

  Widget _buildToolGrid() {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 4,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: _filteredTools.map((tool) {
        final isSelected = _selectedTools.contains(tool.name);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: tool.isInstalled ? null : () => _toggleTool(tool.name),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF2563eb)
                      : const Color(0xFFe2e8f0),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF2563eb)
                              : const Color(0xFFe2e8f0),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFFdce3eb)),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 12,
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tool.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tool.isInstalled
                              ? const Color(0xFFecfdf5)
                              : const Color(0xFFf0f4f8),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          tool.isInstalled ? '已安装' : '未安装',
                          style: TextStyle(
                            fontSize: 9,
                            color: tool.isInstalled
                                ? const Color(0xFF10b981)
                                : const Color(0xFF6b7c93),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tool.description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6b7c93),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tool.command,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6b7c93),
                      fontFamily: 'Monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInstallButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Row(
        children: [
          Text(
            '已选 ${_selectedTools.length} 项',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _isInstalling ? null : _installSelectedTools,
            style: AppButtonStyles.primary(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: _isInstalling
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('一键安装'),
          ),
        ],
      ),
    );
  }
}
