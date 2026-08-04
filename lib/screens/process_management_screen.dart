import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/refresh_scope.dart';
import '../models/query_options.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import '../widgets/app_button_styles.dart';
import '../widgets/sort_header_cell.dart';

class ProcessManagementScreen extends StatefulWidget {
  const ProcessManagementScreen({super.key});

  @override
  State<ProcessManagementScreen> createState() =>
      ProcessManagementScreenState();
}

class ProcessManagementScreenState extends State<ProcessManagementScreen> {
  List<ProcessInfo> _processes = [];
  List<ProcessInfo> _allProcesses = [];
  String _searchText = '';
  String _sortBy = 'cpu';
  bool _sortAscending = false;
  bool _isLoading = false;
  ProcessInfo? _selectedProcess;
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
      provider.onPageEnter(RefreshScope.processes);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<AppProvider>(context);
    final serverId = provider.selectedServer?.id;
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.processes.key];
    if (_lastServerId != serverId) {
      _lastServerId = serverId;
      _lastUpdatedAt = null;
      _selectedProcess = null;
      _applyCache(provider);
      provider.onPageEnter(RefreshScope.processes);
    } else if (updatedAt != null && updatedAt != _lastUpdatedAt) {
      _applyCache(provider);
    }
  }

  void _applyCache(AppProvider provider) {
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.processes.key];
    setState(() {
      _allProcesses = provider.currentCache?.processes ?? [];
      _lastUpdatedAt = updatedAt;
    });
    _reloadProcesses();
  }

  Future<void> _reloadProcesses() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final serverId = provider.selectedServer?.id;
    if (serverId == null) {
      if (!mounted) return;
      setState(() => _processes = []);
      return;
    }
    final items = await provider.storageService.queryProcesses(
      serverId: serverId,
      options: QueryOptions(
        keyword: _searchText,
        sortBy: _sortBy,
        direction: _sortAscending
            ? SortDirection.ascending
            : SortDirection.descending,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _processes = items;
      if (_selectedProcess != null &&
          !_processes.any((item) => item.pid == _selectedProcess!.pid)) {
        _selectedProcess = null;
      }
    });
  }

  void refresh() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) {
      return;
    }
    setState(() => _isLoading = true);
    Future(() async {
      await provider.requestRefreshNow(
        RefreshScope.processes,
        reason: 'processes-refresh',
      );
      if (!mounted) return;
      _applyCache(provider);
      setState(() => _isLoading = false);
    });
  }

  Future<void> _killProcess(int pid, bool force) async {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final provider = Provider.of<AppProvider>(dialogContext, listen: false);
        final navigator = Navigator.of(dialogContext);
        return AlertDialog(
          title: const Text('确认终止'),
          content: Text('确定要${force ? '强制' : ''}终止PID $pid 的进程吗？'),
          actions: [
            TextButton(onPressed: navigator.pop, child: const Text('取消')),
            TextButton(
              onPressed: () async {
                setState(() => _isLoading = true);
                try {
                  await provider.killProcess(pid, force: force);
                  await provider.requestRefreshNow(
                    RefreshScope.processes,
                    reason: 'processes-kill',
                  );
                  if (!mounted) {
                    return;
                  }
                  _applyCache(provider);
                  _showMessage(force ? '已强制终止进程 PID $pid' : '已终止进程 PID $pid');
                } catch (error) {
                  _showMessage('终止进程失败：$error', isError: true);
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                  navigator.pop();
                }
                if (_selectedProcess?.pid == pid) {
                  setState(() => _selectedProcess = null);
                }
              },
              style: AppButtonStyles.textDanger(),
              child: const Text('终止'),
            ),
          ],
        );
      },
    );
  }

  void _showProcessDetail(ProcessInfo process) {
    setState(() => _selectedProcess = process);
  }

  List<ProcessInfo> get _filteredProcesses {
    return _processes;
  }

  List<ProcessInfo> get _topCpuProcesses {
    final sorted = List<ProcessInfo>.from(_allProcesses)
      ..sort((a, b) => b.cpuPercent.compareTo(a.cpuPercent));
    return sorted.take(10).toList();
  }

  List<ProcessInfo> get _topMemoryProcesses {
    final sorted = List<ProcessInfo>.from(_allProcesses)
      ..sort((a, b) => b.memoryPercent.compareTo(a.memoryPercent));
    return sorted.take(10).toList();
  }

  void _toggleSort(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = sortBy == 'name' || sortBy == 'user' || sortBy == 'status';
      }
    });
    _reloadProcesses();
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
          _buildTopProcessCards(),
          const SizedBox(height: 16),
          Expanded(child: _buildProcessTable()),
          if (_selectedProcess != null) _buildProcessDetail(),
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
              decoration: AppFieldStyles.toolbarInput(
                hintText: '搜索进程名称或PID...',
              ),
              onChanged: (text) {
                setState(() => _searchText = text);
                _reloadProcesses();
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: provider.selectedServer == null ? null : refresh,
          style: AppButtonStyles.primary(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('刷新进程列表'),
        ),
      ],
    );
  }

  Widget _buildTopProcessCards() {
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOP 10 CPU 进程',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Column(
                  children: _topCpuProcesses.take(5).map((process) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              process.name,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: AppProgressBar(
                              value: process.cpuPercent / 100,
                              color: const Color(0xFF2563eb),
                              height: 4,
                              radius: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${process.cpuPercent.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOP 10 内存进程',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Column(
                  children: _topMemoryProcesses.take(5).map((process) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              process.name,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: AppProgressBar(
                              value: process.memoryPercent / 100,
                              color: const Color(0xFF10b981),
                              height: 4,
                              radius: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${process.memoryPercent.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProcessTable() {
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
                  label: 'PID',
                  active: _sortBy == 'pid',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('pid'),
                ),
                SortHeaderCell(
                  label: '进程名称',
                  active: _sortBy == 'name',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('name'),
                ),
                SortHeaderCell(
                  label: 'CPU',
                  active: _sortBy == 'cpu',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('cpu'),
                ),
                SortHeaderCell(
                  label: '内存',
                  active: _sortBy == 'memory',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('memory'),
                ),
                SortHeaderCell(
                  label: '状态',
                  active: _sortBy == 'status',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('status'),
                ),
                SortHeaderCell(
                  label: '用户',
                  active: _sortBy == 'user',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('user'),
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
              itemCount: _filteredProcesses.length,
              itemBuilder: (context, index) {
                final process = _filteredProcesses[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: const Border(
                      bottom: BorderSide(color: Color(0xFFf0f4f8)),
                    ),
                    color: _selectedProcess?.pid == process.pid
                        ? const Color(0xFFeff6ff)
                        : Colors.white,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          process.pid.toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showProcessDetail(process),
                          child: Text(
                            process.name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2563eb),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${process.cpuPercent.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${process.memoryPercent.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: process.status == 'R'
                                ? const Color(0xFFecfdf5)
                                : process.status == 'S'
                                ? const Color(0xFFeff6ff)
                                : const Color(0xFFf0f4f8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            process.status,
                            style: TextStyle(
                              fontSize: 11,
                              color: process.status == 'R'
                                  ? const Color(0xFF10b981)
                                  : process.status == 'S'
                                  ? const Color(0xFF2563eb)
                                  : const Color(0xFF6b7c93),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          process.user,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            AppIconActionButton(
                              icon: Icons.pause,
                              tooltip: '终止进程',
                              onPressed: () => _killProcess(process.pid, false),
                              foregroundColor: const Color(0xFFf59e0b),
                              backgroundColor: const Color(0xFFfffbeb),
                            ),
                            const SizedBox(width: 8),
                            AppIconActionButton(
                              icon: Icons.stop,
                              tooltip: '强制终止进程',
                              onPressed: () => _killProcess(process.pid, true),
                              foregroundColor: const Color(0xFFef4444),
                              backgroundColor: const Color(0xFFfef2f2),
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

  Widget _buildProcessDetail() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFeff6ff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2563eb)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '进程详情:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _selectedProcess = null),
                child: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '命令: ',
                style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
              ),
              Expanded(
                child: Text(
                  _selectedProcess!.command,
                  style: const TextStyle(fontSize: 12, fontFamily: 'Monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
