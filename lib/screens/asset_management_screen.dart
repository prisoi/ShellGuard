import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/query_options.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import '../services/storage_service.dart';
import '../widgets/adaptive_page_layout.dart';
import '../widgets/app_button_styles.dart';

class AssetManagementScreen extends StatefulWidget {
  const AssetManagementScreen({super.key});

  @override
  State<AssetManagementScreen> createState() => _AssetManagementScreenState();
}

class _AssetManagementScreenState extends State<AssetManagementScreen> {
  List<Server> _filteredServers = [];
  String _searchText = '';
  String _selectedGroup = '全部';
  String _sortBy = 'name';
  bool _sortAscending = true;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _serverGroup = '默认分组';
  Server? _editingServer;
  bool _isBatchCheckingConnectivity = false;
  bool _isExportingConfigs = false;
  bool _isImportingConfigs = false;
  String? _bulkActionStatus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadServers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _reloadServers() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final items = await provider.storageService.queryServers(
      options: QueryOptions(
        keyword: _searchText,
        sortBy: _sortBy,
        direction: _sortAscending
            ? SortDirection.ascending
            : SortDirection.descending,
        filters: {'group': _selectedGroup},
      ),
    );
    if (!mounted) return;
    setState(() => _filteredServers = items);
  }

  void _showAddServerDialog() {
    _editingServer = null;
    _nameController.clear();
    _ipController.clear();
    _portController.text = '22';
    _usernameController.clear();
    _passwordController.clear();
    _serverGroup = '默认分组';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加服务器'),
        content: _buildServerForm(),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: _saveServer,
            style: AppButtonStyles.primary(),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showEditServerDialog(Server server) {
    _editingServer = server;
    _nameController.text = server.name;
    _ipController.text = server.ip;
    _portController.text = server.port.toString();
    _usernameController.text = server.username;
    _passwordController.text = server.password;
    _serverGroup = server.group;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑服务器'),
        content: _buildServerForm(),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(onPressed: _saveServer, child: const Text('保存')),
        ],
      ),
    );
  }

  void _saveServer() {
    if (!_formKey.currentState!.validate()) return;

    final provider = Provider.of<AppProvider>(context, listen: false);
    final server = Server(
      id:
          _editingServer?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      ip: _ipController.text,
      port: int.parse(_portController.text),
      username: _usernameController.text,
      password: _passwordController.text,
      group: _serverGroup,
    );

    if (_editingServer != null) {
      provider.updateServer(server);
    } else {
      provider.addServer(server);
    }

    Navigator.pop(context);
    _reloadServers();
  }

  void _deleteServer(String serverId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这台服务器吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<AppProvider>(
                context,
                listen: false,
              ).deleteServer(serverId);
              Navigator.pop(context);
              _reloadServers();
            },
            style: AppButtonStyles.textDanger(),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFdc2626) : null,
      ),
    );
  }

  Future<String> _resolveDefaultJsonDirectory() async {
    final downloadsDirectory = await getDownloadsDirectory();
    final fallbackPath = Platform.isWindows
        ? p.join(
            Platform.environment['USERPROFILE'] ?? Directory.current.path,
            'Downloads',
          )
        : p.join(
            Platform.environment['HOME'] ?? Directory.current.path,
            'Downloads',
          );
    final resolvedPath = downloadsDirectory?.path ?? fallbackPath;
    await Directory(resolvedPath).create(recursive: true);
    return resolvedPath;
  }

  String _buildExportFileName() {
    final now = DateTime.now();
    final compact =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return 'shellguard_servers_$compact.json';
  }

  Future<void> _batchCheckConnectivity() async {
    if (_filteredServers.isEmpty || _isBatchCheckingConnectivity) {
      _showSnackBar('当前没有可检测的服务器');
      return;
    }

    final provider = Provider.of<AppProvider>(context, listen: false);
    setState(() {
      _isBatchCheckingConnectivity = true;
      _bulkActionStatus = '准备检测 ${_filteredServers.length} 台服务器的连通性...';
    });

    try {
      final result = await provider.batchCheckConnectivity(
        targets: _filteredServers,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            final suffix = progress.isOnline == null
                ? '正在连接 ${progress.server.name}'
                : '${progress.server.name} ${progress.isOnline! ? '在线' : '离线'}';
            _bulkActionStatus =
                '批量检测 ${progress.completed}/${progress.total}，$suffix';
          });
        },
      );
      await _reloadServers();
      if (!mounted) {
        return;
      }
      setState(() {
        _bulkActionStatus =
            '批量检测完成：${result.checkedCount} 台，在线 ${result.onlineCount}，离线 ${result.offlineCount}';
      });
      _showBatchCheckResultDialog(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _bulkActionStatus = '批量检测失败：$error');
      _showSnackBar('批量检测失败：$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isBatchCheckingConnectivity = false);
      }
    }
  }

  Future<void> _exportServers() async {
    if (_filteredServers.isEmpty || _isExportingConfigs) {
      _showSnackBar('当前没有可导出的服务器');
      return;
    }

    setState(() {
      _isExportingConfigs = true;
      _bulkActionStatus = '正在准备导出 ${_filteredServers.length} 台服务器配置...';
    });

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final saveLocation = await getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
        initialDirectory: await _resolveDefaultJsonDirectory(),
        suggestedName: _buildExportFileName(),
        confirmButtonText: '导出配置',
      );
      if (saveLocation == null) {
        if (mounted) {
          setState(() => _bulkActionStatus = '已取消导出');
        }
        return;
      }

      final result = await provider.storageService.exportServersToJson(
        servers: _filteredServers,
        targetPath: saveLocation.path,
      );
      if (!mounted) {
        return;
      }
      setState(
        () => _bulkActionStatus =
            '已导出 ${result.exportedCount} 台服务器到 ${result.path}',
      );
      _showSnackBar('导出成功：${result.exportedCount} 台服务器');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _bulkActionStatus = '导出失败：$error');
      _showSnackBar('导出失败：$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isExportingConfigs = false);
      }
    }
  }

  Future<void> _importServers() async {
    if (_isImportingConfigs) {
      return;
    }

    setState(() {
      _isImportingConfigs = true;
      _bulkActionStatus = '等待选择要导入的 JSON 配置文件...';
    });

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
        initialDirectory: await _resolveDefaultJsonDirectory(),
        confirmButtonText: '导入配置',
      );
      if (file == null) {
        if (mounted) {
          setState(() => _bulkActionStatus = '已取消导入');
        }
        return;
      }

      final remainingSlots =
          AppProvider.freeServerLimit - provider.servers.length;
      final result = await provider.storageService.importServersFromJson(
        filePath: file.path,
        maxAdditionalServers: remainingSlots < 0 ? 0 : remainingSlots,
      );
      await provider.reloadServers(notify: false);
      await _reloadServers();
      if (!mounted) {
        return;
      }
      setState(() {
        _bulkActionStatus =
            '导入完成：新增 ${result.importedCount} 台，跳过重复 ${result.duplicateSkippedCount} 台';
      });
      await _showImportResultDialog(result);
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _bulkActionStatus = '导入失败：${error.message}');
      _showSnackBar('导入失败：${error.message}', isError: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _bulkActionStatus = '导入失败：$error');
      _showSnackBar('导入失败：$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isImportingConfigs = false);
      }
    }
  }

  Future<void> _showImportResultDialog(ServerConfigImportResult result) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入结果'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('新增 ${result.importedCount} 台服务器'),
              const SizedBox(height: 6),
              Text('跳过重复 ${result.duplicateSkippedCount} 台'),
              const SizedBox(height: 6),
              Text('自动改名 ${result.renamedCount} 台'),
              const SizedBox(height: 6),
              Text('无效记录 ${result.invalidCount} 条'),
              if (result.limitSkippedCount > 0) ...[
                const SizedBox(height: 6),
                Text('超出数量上限 ${result.limitSkippedCount} 台'),
              ],
              if (result.renamedEntries.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  '自动改名',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...result.renamedEntries.take(5).map(
                  (entry) => Text(
                    '• ${entry.name} (${entry.ip}) ${entry.detail}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (result.skippedEntries.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  '已跳过项目',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...result.skippedEntries.take(5).map(
                  (entry) => Text(
                    '• ${entry.name} (${entry.ip}) ${entry.detail}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                '说明：导入仅新增本地不存在的服务器，不会覆盖当前本地配置；同 IP 冲突但非完全重复的条目会自动加名称后缀。',
                style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showBatchCheckResultDialog(BatchConnectivityCheckResult result) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量检测结果'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('已检测 ${result.checkedCount} 台服务器'),
              const SizedBox(height: 6),
              Text('在线 ${result.onlineCount} 台'),
              const SizedBox(height: 6),
              Text('离线 ${result.offlineCount} 台'),
              if (result.failedServers.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '离线服务器',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...result.failedServers.take(6).map(
                  (server) => Text(
                    '• ${server.name} (${server.ip}:${server.port})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildServerForm() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final groupOptions = {'默认分组', ...provider.groups}.toList()..sort();

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: AppFieldStyles.outlined(labelText: '服务器名称'),
            validator: (value) => value?.isEmpty ?? true ? '请输入服务器名称' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _ipController,
                  decoration: AppFieldStyles.outlined(labelText: 'IP地址'),
                  validator: (value) =>
                      value?.isEmpty ?? true ? '请输入IP地址' : null,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextFormField(
                  controller: _portController,
                  decoration: AppFieldStyles.outlined(labelText: '端口'),
                  validator: (value) =>
                      int.tryParse(value ?? '') == null ? '请输入有效端口' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _usernameController,
                  decoration: AppFieldStyles.outlined(labelText: '用户名'),
                  validator: (value) =>
                      value?.isEmpty ?? true ? '请输入用户名' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _passwordController,
                  decoration: AppFieldStyles.outlined(labelText: '密码'),
                  obscureText: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _serverGroup,
            decoration: AppFieldStyles.outlined(labelText: '所属分组'),
            items: groupOptions
                .map(
                  (group) => DropdownMenuItem<String>(
                    value: group,
                    child: Text(group),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _serverGroup = value);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return AdaptivePageLayout(
      estimatedReservedHeight: 360,
      minBodyHeight: 260,
      header: [_buildTopBar(provider), const SizedBox(height: 16)],
      body: _buildServerCards(),
      footer: [
        const SizedBox(height: 16),
        _buildServerQuota(provider),
        const SizedBox(height: 16),
        _buildSidePanel(provider),
      ],
    );
  }

  Widget _buildTopBar(AppProvider provider) {
    return Row(
      children: [
        ElevatedButton(
          onPressed: provider.canAddMoreServers ? _showAddServerDialog : null,
          style: AppButtonStyles.primary(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text('+ 添加服务器'),
        ),
        const SizedBox(width: 16),
        AppControlShell(
          width: 140,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedGroup,
              isExpanded: true,
              items: ['全部', ...provider.groups].map((group) {
                return DropdownMenuItem(value: group, child: Text(group));
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedGroup = value!);
                _reloadServers();
              },
              style: const TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        AppControlShell(
          width: 180,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: '$_sortBy:${_sortAscending ? 'asc' : 'desc'}',
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'name:asc', child: Text('名称 A-Z')),
                DropdownMenuItem(value: 'name:desc', child: Text('名称 Z-A')),
                DropdownMenuItem(value: 'ip:asc', child: Text('IP 升序')),
                DropdownMenuItem(value: 'ip:desc', child: Text('IP 降序')),
                DropdownMenuItem(value: 'group:asc', child: Text('分组升序')),
                DropdownMenuItem(value: 'status:desc', child: Text('在线优先')),
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
                _reloadServers();
              },
            ),
          ),
        ),
        const Spacer(),
        AppControlShell(
          width: 200,
          child: TextField(
            decoration: AppFieldStyles.toolbarInput(hintText: '搜索服务器...'),
            onChanged: (text) {
              setState(() => _searchText = text);
              _reloadServers();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildServerCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth;
        final crossAxisCount = gridWidth >= 1180
            ? 3
            : gridWidth >= 760
            ? 2
            : 1;
        return GridView.count(
          shrinkWrap: true,
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: crossAxisCount == 1 ? 2.8 : 2.25,
          children: _filteredServers.map((server) {
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
                  Row(
                    children: [
                      Icon(
                        server.isOnline ? Icons.check_circle : Icons.circle,
                        color: server.isOnline
                            ? const Color(0xFF10b981)
                            : const Color(0xFFef4444),
                        size: 12,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          server.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: server.group == '生产环境'
                              ? const Color(0xFFeff6ff)
                              : server.group == '测试环境'
                              ? const Color(0xFFfffbeb)
                              : const Color(0xFFfef2f2),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          server.group,
                          style: TextStyle(
                            fontSize: 10,
                            color: server.group == '生产环境'
                                ? const Color(0xFF2563eb)
                                : server.group == '测试环境'
                                ? const Color(0xFFf59e0b)
                                : const Color(0xFFef4444),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${server.ip}:${server.port}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6b7c93),
                      fontFamily: 'Monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    server.osInfo ?? '未知系统',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6b7c93),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: server.isOnline
                              ? const Color(0xFFecfdf5)
                              : const Color(0xFFfef2f2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          server.isOnline ? '在线' : '离线',
                          style: TextStyle(
                            fontSize: 10,
                            color: server.isOnline
                                ? const Color(0xFF10b981)
                                : const Color(0xFFef4444),
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showEditServerDialog(server),
                        child: const Icon(
                          Icons.edit,
                          color: Color(0xFF6b7c93),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _deleteServer(server.id),
                        child: const Icon(
                          Icons.delete,
                          color: Color(0xFFef4444),
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildServerQuota(AppProvider provider) {
    final used = provider.servers.length;
    final total = 10;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFf8fafc),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Row(
        children: [
          const Text(
            '服务器配额：',
            style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 200,
            child: AppProgressBar(
              value: used / total,
              color: const Color(0xFF2563eb),
              height: 14,
              radius: 7,
              backgroundColor: const Color(0xFFe2e8f0),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$used / $total',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          Text(
            '（个人免费版最多 10 台服务器）',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6b7c93)),
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanel(AppProvider provider) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Container(
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
                  '分组管理',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...provider.groups.map((group) {
                  final count = provider.servers
                      .where((s) => s.group == group)
                      .length;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _selectedGroup == group
                          ? const Color(0xFFeff6ff)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder,
                          size: 14,
                          color: Color(0xFF6b7c93),
                        ),
                        const SizedBox(width: 8),
                        Text(group, style: const TextStyle(fontSize: 12)),
                        const Spacer(),
                        Text(
                          '($count)',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6b7c93),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFFe2e8f0)),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        final controller = TextEditingController();
                        return AlertDialog(
                          title: const Text('新建分组'),
                          content: TextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              labelText: '分组名称',
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                provider.addGroup(value);
                                Navigator.pop(context);
                              }
                            },
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () {
                                final value = controller.text.trim();
                                if (value.isNotEmpty) {
                                  provider.addGroup(value);
                                }
                                Navigator.pop(context);
                              },
                              child: const Text('确定'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  style: AppButtonStyles.secondary(),
                  child: const Text('+ 新建分组'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 7,
          child: Container(
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
                  '批量操作',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildBulkActionTile(
                  icon: Icons.network_check,
                  title: '批量检测连通性',
                  description: '对当前筛选结果中的服务器逐台检测 SSH 连通状态。',
                  accentColor: const Color(0xFF2563eb),
                  backgroundColor: const Color(0xFFeff6ff),
                  onTap: _isBatchCheckingConnectivity ? null : _batchCheckConnectivity,
                  isLoading: _isBatchCheckingConnectivity,
                ),
                const SizedBox(height: 8),
                _buildBulkActionTile(
                  icon: Icons.file_download_outlined,
                  title: '导出服务器列表',
                  description: '将当前筛选结果导出为 JSON，便于备份或迁移。',
                  accentColor: const Color(0xFF2563eb),
                  backgroundColor: const Color(0xFFeff6ff),
                  onTap: _isExportingConfigs ? null : _exportServers,
                  isLoading: _isExportingConfigs,
                ),
                const SizedBox(height: 8),
                _buildBulkActionTile(
                  icon: Icons.file_upload_outlined,
                  title: '导入 SSH 配置',
                  description: '从 JSON 合并导入服务器配置，自动查重且不覆盖本地已有数据。',
                  accentColor: const Color(0xFFd97706),
                  backgroundColor: const Color(0xFFfffbeb),
                  onTap: _isImportingConfigs ? null : _importServers,
                  isLoading: _isImportingConfigs,
                ),
                if (_bulkActionStatus != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFf8fafc),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFe2e8f0)),
                    ),
                    child: Text(
                      _bulkActionStatus!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFe2e8f0)),
                const SizedBox(height: 8),
                const Text(
                  '提示: 导入仅做追加合并，不会覆盖当前本地配置；完全重复的服务器会跳过，同 IP 冲突会自动加名称后缀便于后续人工整理。',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6b7c93)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBulkActionTile({
    required IconData icon,
    required String title,
    required String description,
    required Color accentColor,
    required Color backgroundColor,
    required VoidCallback? onTap,
    required bool isLoading,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: onTap == null
                  ? const Color(0xFFdbe3ec)
                  : accentColor.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748b),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    )
                  : Icon(Icons.chevron_right, color: accentColor),
            ],
          ),
        ),
      ),
    );
  }
}
