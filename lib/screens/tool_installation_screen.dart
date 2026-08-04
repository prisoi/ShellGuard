import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import '../widgets/app_button_styles.dart';

enum ToolInstallState {
  idle,
  checking,
  installing,
  installed,
  failed,
}

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
  String? _installSummary;
  final Map<String, ToolInstallState> _toolStates = {};
  final Map<String, String> _toolMessages = {};
  String? _lastServerId;

  @override
  void initState() {
    super.initState();
    _loadTools();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateToolStatesFromCache();
    });
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
        name: 'uv',
        category: '开发工具',
        description: '极速 Python 包与虚拟环境管理工具',
        command: 'curl -LsSf https://astral.sh/uv/install.sh | sh',
      ),
      ToolInfo(
        name: 'ufw',
        category: '防火墙',
        description: '自动按系统安装 ufw 或 firewalld',
        command: 'auto install firewall tool',
      ),
      ToolInfo(
        name: 'docker',
        category: 'Docker',
        description: 'Docker 引擎',
        command: 'auto install docker engine',
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

  void _hydrateToolStatesFromCache() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final cachedInstalledTools = provider.getSelectedInstalledToolsCache();
    if (cachedInstalledTools.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _lastServerId = provider.selectedServer?.id;
      for (var i = 0; i < _tools.length; i++) {
        final installed = cachedInstalledTools[_tools[i].name];
        if (installed == null) {
          continue;
        }
        _tools[i] = _tools[i].copyWith(isInstalled: installed);
        _toolStates[_tools[i].name] =
            installed ? ToolInstallState.installed : ToolInstallState.idle;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<AppProvider>(context);
    if (_lastServerId != provider.selectedServer?.id) {
      _toolMessages.clear();
      _toolStates.clear();
      _selectedTools.clear();
      _installSummary = null;
      _hydrateToolStatesFromCache();
    }
  }

  String _commandForTool(AppProvider provider, ToolInfo tool) {
    return provider.buildInstallToolCommand(tool.name);
  }

  Future<void> _checkInstalledStatus() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isConnected) {
      _showStatusMessage('请先连接服务器，再检查工具状态', isError: true);
      return;
    }

    setState(() {
      _installSummary = '正在检查工具安装状态...';
      for (final tool in _tools) {
        _toolStates[tool.name] = ToolInstallState.checking;
      }
    });

    final installedMap = <String, bool>{};
    try {
      for (var i = 0; i < _tools.length; i++) {
        final tool = _tools[i];
        final installed = await provider.checkToolInstalledSelected(tool.name);
        installedMap[tool.name] = installed;
        if (!mounted) {
          return;
        }
        setState(() {
          _tools[i] = _tools[i].copyWith(isInstalled: installed);
          _toolStates[tool.name] = installed
              ? ToolInstallState.installed
              : ToolInstallState.idle;
          _toolMessages.remove(tool.name);
          _installSummary =
              '正在检查工具安装状态...（${i + 1}/${_tools.length}）';
        });
      }
      await provider.persistInstalledToolScanSelected(installedMap);
      if (!mounted) {
        return;
      }
      setState(() {
        _installSummary = '工具状态已刷新并同步到数据库';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        for (final tool in _tools) {
          if (_toolStates[tool.name] == ToolInstallState.checking) {
            _toolStates[tool.name] = ToolInstallState.failed;
          }
        }
        _installSummary = '工具状态刷新失败';
      });
      _showStatusMessage(
        '状态检查失败：${error.toString().replaceFirst('Exception: ', '')}',
        isError: true,
      );
      return;
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
    if (!provider.isConnected) {
      _showStatusMessage('请先连接服务器，再执行安装', isError: true);
      return;
    }
    if (_selectedTools.isEmpty) {
      _showStatusMessage('请先选择要安装的工具', isError: true);
      return;
    }

    setState(() => _isInstalling = true);

    final selectedTools = List<String>.from(_selectedTools);
    final totalCount = selectedTools.length;
    var successCount = 0;
    for (final tool in selectedTools) {
      final installed = await _installTool(
        tool,
        showFeedback: false,
        removeSelectionOnSuccess: false,
      );
      if (installed) {
        successCount++;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isInstalling = false;
      _selectedTools.clear();
      _installSummary = '批量安装完成：成功 $successCount / $totalCount';
    });
  }

  Future<bool> _installTool(
    String toolName, {
    bool showFeedback = true,
    bool removeSelectionOnSuccess = true,
  }) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isConnected) {
      if (showFeedback) {
        _showStatusMessage('请先连接服务器，再执行安装', isError: true);
      }
      return false;
    }

    setState(() {
      _toolStates[toolName] = ToolInstallState.installing;
      _toolMessages[toolName] = '正在安装...';
      _installSummary = '正在安装 $toolName...';
    });

    try {
      final result = await provider.installToolSelected(toolName);
      final installed = await provider.checkToolInstalledSelected(toolName);
      final index = _tools.indexWhere((tool) => tool.name == toolName);
      final output = result.trim().isEmpty ? '安装命令已执行' : result.trim();

      if (!mounted) {
        return installed;
      }

      setState(() {
        if (index != -1) {
          _tools[index] = _tools[index].copyWith(isInstalled: installed);
        }
        _toolStates[toolName] = installed
            ? ToolInstallState.installed
            : ToolInstallState.failed;
        _toolMessages[toolName] = installed ? '安装成功' : output;
        _installSummary = installed ? '$toolName 安装成功' : '$toolName 安装失败';
        if (installed && removeSelectionOnSuccess) {
          _selectedTools.remove(toolName);
        }
      });

      if (showFeedback) {
        _showStatusMessage(
          installed ? '$toolName 安装成功' : '$toolName 安装失败：$output',
          isError: !installed,
        );
      }
      return installed;
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      if (!mounted) {
        return false;
      }
      setState(() {
        _toolStates[toolName] = ToolInstallState.failed;
        _toolMessages[toolName] = message;
        _installSummary = '$toolName 安装失败';
      });
      if (showFeedback) {
        _showStatusMessage('$toolName 安装失败：$message', isError: true);
      }
      return false;
    }
  }

  void _showStatusMessage(String message, {bool isError = false}) {
    setState(() {
      _installSummary = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFef4444) : null,
      ),
    );
  }

  ToolInstallState _toolStateFor(ToolInfo tool) {
    return _toolStates[tool.name] ??
        (tool.isInstalled ? ToolInstallState.installed : ToolInstallState.idle);
  }

  String _toolStatusLabel(ToolInfo tool) {
    final state = _toolStateFor(tool);
    switch (state) {
      case ToolInstallState.checking:
        return '检查中';
      case ToolInstallState.installing:
        return '安装中';
      case ToolInstallState.installed:
        return '已安装';
      case ToolInstallState.failed:
        return '失败';
      case ToolInstallState.idle:
        return tool.isInstalled ? '已安装' : '未安装';
    }
  }

  Color _toolStatusColor(ToolInfo tool) {
    final state = _toolStateFor(tool);
    switch (state) {
      case ToolInstallState.checking:
        return const Color(0xFF2563eb);
      case ToolInstallState.installing:
        return const Color(0xFFf59e0b);
      case ToolInstallState.installed:
        return const Color(0xFF10b981);
      case ToolInstallState.failed:
        return const Color(0xFFef4444);
      case ToolInstallState.idle:
        return const Color(0xFF6b7c93);
    }
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
        if (_installSummary != null) ...[
          _buildStatusBanner(),
          const SizedBox(height: 16),
        ],
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            '当前包管理器: ${provider.currentSystemInfo?.packageManager.isNotEmpty == true ? provider.currentSystemInfo!.packageManager : provider.selectedServer?.packageManager ?? '未知'}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6b7c93)),
          ),
        ),
        const SizedBox(width: 12),
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
      childAspectRatio: 0.92,
      children: _filteredTools.map((tool) {
        final isSelected = _selectedTools.contains(tool.name);
        final statusColor = _toolStatusColor(tool);
        final state = _toolStateFor(tool);
        final toolMessage = _toolMessages[tool.name];
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
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          _toolStatusLabel(tool),
                          style: TextStyle(
                            fontSize: 9,
                            color: statusColor,
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
                    _commandForTool(Provider.of<AppProvider>(context, listen: false), tool),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6b7c93),
                      fontFamily: 'Monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (toolMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      toolMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: state == ToolInstallState.failed
                            ? const Color(0xFFef4444)
                            : const Color(0xFF6b7c93),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: state == ToolInstallState.installing || tool.isInstalled
                              ? null
                              : () => _installTool(tool.name),
                          style: state == ToolInstallState.failed
                              ? AppButtonStyles.warning(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                )
                              : AppButtonStyles.primary(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                          child: state == ToolInstallState.installing
                              ? const SizedBox(
                                  height: 14,
                                  width: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(tool.isInstalled ? '已安装' : '安装'),
                        ),
                      ),
                    ],
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
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text('一键安装'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final summary = _installSummary;
    if (summary == null || summary.isEmpty) {
      return const SizedBox.shrink();
    }
    final isError = summary.contains('失败');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isError
            ? const Color(0xFFfef2f2)
            : const Color(0xFFeff6ff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError
              ? const Color(0xFFfecaca)
              : const Color(0xFFbfdbfe),
        ),
      ),
      child: Text(
        summary,
        style: TextStyle(
          fontSize: 12,
          color: isError ? const Color(0xFFb91c1c) : const Color(0xFF1d4ed8),
        ),
      ),
    );
  }
}
