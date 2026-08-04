import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/refresh_scope.dart';
import '../models/query_options.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import '../widgets/app_button_styles.dart';
import '../widgets/sort_header_cell.dart';

class ServiceManagementScreen extends StatefulWidget {
  const ServiceManagementScreen({super.key});

  @override
  State<ServiceManagementScreen> createState() =>
      ServiceManagementScreenState();
}

class ServiceManagementScreenState extends State<ServiceManagementScreen> {
  List<ServiceInfo> _services = [];
  String _searchText = '';
  String _sortBy = 'status';
  bool _sortAscending = false;
  bool _isLoading = false;
  String? _lastServerId;
  String? _lastUpdatedAt;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFDC2626) : null,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      _applyCache(provider);
      provider.onPageEnter(RefreshScope.services);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<AppProvider>(context);
    final serverId = provider.selectedServer?.id;
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.services.key];
    if (_lastServerId != serverId) {
      _lastServerId = serverId;
      _lastUpdatedAt = null;
      _applyCache(provider);
      provider.onPageEnter(RefreshScope.services);
    } else if (updatedAt != null && updatedAt != _lastUpdatedAt) {
      _applyCache(provider);
    }
  }

  void _applyCache(AppProvider provider) {
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.services.key];
    setState(() {
      _lastUpdatedAt = updatedAt;
    });
    _reloadServices();
  }

  Future<void> _reloadServices() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final serverId = provider.selectedServer?.id;
    if (serverId == null) {
      if (!mounted) return;
      setState(() => _services = []);
      return;
    }
    final items = await provider.storageService.queryServices(
      serverId: serverId,
      options: QueryOptions(
        keyword: _searchText,
        sortBy: _sortBy,
        direction: _sortAscending
            ? SortDirection.ascending
            : SortDirection.descending,
      ),
    );
    if (!mounted) return;
    setState(() => _services = items);
  }

  void refresh() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) {
      return;
    }
    setState(() => _isLoading = true);
    Future(() async {
      await provider.requestRefreshNow(
        RefreshScope.services,
        reason: 'services-refresh',
      );
      if (!mounted) return;
      _applyCache(provider);
      setState(() => _isLoading = false);
    });
  }

  Future<void> _manageService(String name, String action) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isConnected) return;

    setState(() => _isLoading = true);
    try {
      await provider.manageServiceSelected(
        serviceName: name,
        action: action,
      );
      await provider.requestRefreshNow(
        RefreshScope.services,
        reason: 'services-manage',
      );
      if (!mounted) return;
      _applyCache(provider);
      _showMessage('服务 $name 已执行 $action');
    } catch (error) {
      _showMessage('服务操作失败：$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showServiceLogs(String name) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isConnected) return;

    showDialog(
      context: context,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    String logs = '';
    try {
      logs = await provider.getServiceLogsSelected(name);
    } catch (e) {
      logs = '获取日志失败: $e';
    }

    if (!mounted) return;
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name 日志'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: SelectableText(
              logs.trim().isEmpty ? '暂无日志输出' : logs,
              style: const TextStyle(fontFamily: 'Monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: AppButtonStyles.text(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateServiceDialog() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isConnected) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final execController = TextEditingController();
    final argsController = TextEditingController();
    final workingDirController = TextEditingController(text: '/');
    final logPathController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('托管业务程序'),
        content: SizedBox(
          width: 560,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: AppFieldStyles.outlined(labelText: '服务名称'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入服务名称'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descriptionController,
                    decoration: AppFieldStyles.outlined(labelText: '服务描述'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: execController,
                    decoration: AppFieldStyles.outlined(labelText: '执行文件路径'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入执行文件路径'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: argsController,
                    decoration: AppFieldStyles.outlined(labelText: '启动参数'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: workingDirController,
                    decoration: AppFieldStyles.outlined(labelText: '工作目录'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入工作目录'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: logPathController,
                    decoration: AppFieldStyles.outlined(
                      labelText: '日志输出路径(可选)',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: AppButtonStyles.text(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                await provider.createManagedServiceSelected(
                  serviceName: nameController.text.trim(),
                  execStart: execController.text.trim(),
                  workingDirectory: workingDirController.text.trim(),
                  description: descriptionController.text.trim(),
                  arguments: argsController.text.trim(),
                  logPath: logPathController.text.trim(),
                );
                await provider.requestRefreshNow(
                  RefreshScope.services,
                  reason: 'services-create',
                );
                if (!mounted) return;
                _applyCache(provider);
                _showMessage('托管服务已创建并启用');
              } catch (error) {
                _showMessage('创建托管服务失败：$error', isError: true);
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            style: AppButtonStyles.primary(),
            child: const Text('创建并启用'),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return '运行中';
      case 'failed':
        return '失败';
      case 'activating':
        return '启动中';
      default:
        return '已停止';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF10b981);
      case 'failed':
        return const Color(0xFFef4444);
      case 'activating':
        return const Color(0xFF2563eb);
      default:
        return const Color(0xFF6b7c93);
    }
  }

  List<ServiceInfo> get _filteredServices {
    return _services;
  }

  void _toggleSort(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = sortBy == 'name' || sortBy == 'description';
      }
    });
    _reloadServices();
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
          _buildStatusCards(),
          const SizedBox(height: 16),
          Expanded(child: _buildServicesTable()),
        ],
      ),
    );
  }

  Widget _buildTopBar(AppProvider provider) {
    return Row(
      children: [
        Expanded(
          child: AppControlShell(
            child: TextField(
              decoration: AppFieldStyles.toolbarInput(hintText: '搜索服务名称或描述...'),
              onChanged: (text) {
                setState(() => _searchText = text);
                _reloadServices();
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: provider.isConnected ? _showCreateServiceDialog : null,
          style: AppButtonStyles.secondary(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('托管业务程序'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: provider.selectedServer == null ? null : refresh,
          style: AppButtonStyles.primary(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('刷新服务列表'),
        ),
      ],
    );
  }

  Widget _buildStatusCards() {
    final running = _services.where((s) => s.status == 'active').length;
    final stopped = _services
        .where((s) => s.status != 'active' && s.status != 'failed')
        .length;
    final failed = _services.where((s) => s.status == 'failed').length;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFe2e8f0)),
            ),
            child: Column(
              children: [
                const Text(
                  '运行中',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
                ),
                const SizedBox(height: 8),
                Text(
                  running.toString(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10b981),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFe2e8f0)),
            ),
            child: Column(
              children: [
                const Text(
                  '已停止',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
                ),
                const SizedBox(height: 8),
                Text(
                  stopped.toString(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6b7c93),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFe2e8f0)),
            ),
            child: Column(
              children: [
                const Text(
                  '失败',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
                ),
                const SizedBox(height: 8),
                Text(
                  failed.toString(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFef4444),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServicesTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFe2e8f0))),
            ),
            child: Row(
              children: [
                SortHeaderCell(
                  label: '服务名称',
                  active: _sortBy == 'name',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('name'),
                ),
                SortHeaderCell(
                  label: '描述',
                  active: _sortBy == 'description',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('description'),
                ),
                SortHeaderCell(
                  label: '状态',
                  active: _sortBy == 'status',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('status'),
                ),
                SortHeaderCell(
                  label: '开机自启',
                  active: _sortBy == 'enabled',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('enabled'),
                ),
                Expanded(
                  child: Text(
                    '操作',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6b7c93),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredServices.length,
              itemBuilder: (context, index) {
                final service = _filteredServices[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFf0f4f8)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          service.name,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          service.description.isNotEmpty
                              ? service.description
                              : '-',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6b7c93),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: service.status == 'active'
                                ? const Color(0xFFecfdf5)
                                : service.status == 'failed'
                                ? const Color(0xFFfef2f2)
                                : const Color(0xFFf0f4f8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _statusLabel(service.status),
                            style: TextStyle(
                              fontSize: 11,
                              color: _statusColor(service.status),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: service.isEnabled
                                ? const Color(0xFFecfdf5)
                                : const Color(0xFFf0f4f8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            service.isEnabled ? '是' : '否',
                            style: TextStyle(
                              fontSize: 11,
                              color: service.isEnabled
                                  ? const Color(0xFF10b981)
                                  : const Color(0xFF6b7c93),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: '启动服务',
                              onPressed: () => _manageService(service.name, 'start'),
                              splashRadius: 18,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.play_arrow,
                                color: Color(0xFF10b981),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '停止服务',
                              onPressed: () => _manageService(service.name, 'stop'),
                              splashRadius: 18,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.stop,
                                color: Color(0xFFef4444),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '重启服务',
                              onPressed: () => _manageService(service.name, 'restart'),
                              splashRadius: 18,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.refresh,
                                color: Color(0xFF2563eb),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '重载服务',
                              onPressed: () => _manageService(service.name, 'reload'),
                              splashRadius: 18,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.sync,
                                color: Color(0xFFf59e0b),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: service.isEnabled ? '关闭开机自启' : '开启开机自启',
                              onPressed: () => _manageService(
                                service.name,
                                service.isEnabled ? 'disable' : 'enable',
                              ),
                              splashRadius: 18,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                service.isEnabled
                                    ? Icons.toggle_on
                                    : Icons.toggle_off,
                                color: const Color(0xFF6b7c93),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '查看服务日志',
                              onPressed: () => _showServiceLogs(service.name),
                              splashRadius: 18,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.article_outlined,
                                color: Color(0xFF1a2332),
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
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
}
