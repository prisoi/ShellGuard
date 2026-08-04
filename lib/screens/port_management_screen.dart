import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/refresh_scope.dart';
import '../models/query_options.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import '../widgets/app_button_styles.dart';
import '../widgets/sort_header_cell.dart';

class PortManagementScreen extends StatefulWidget {
  const PortManagementScreen({super.key});

  @override
  State<PortManagementScreen> createState() => PortManagementScreenState();
}

class PortManagementScreenState extends State<PortManagementScreen> {
  List<PortInfo> _ports = [];
  String _searchText = '';
  String _sortBy = 'port';
  bool _sortAscending = true;
  bool _isLoading = false;
  String? _lastServerId;
  String? _lastUpdatedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      _applyCache(provider);
      provider.onPageEnter(RefreshScope.ports);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<AppProvider>(context);
    final serverId = provider.selectedServer?.id;
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.ports.key];
    if (_lastServerId != serverId) {
      _lastServerId = provider.selectedServer?.id;
      _lastUpdatedAt = null;
      _applyCache(provider);
      provider.onPageEnter(RefreshScope.ports);
    } else if (updatedAt != null && updatedAt != _lastUpdatedAt) {
      _applyCache(provider);
    }
  }

  void _applyCache(AppProvider provider) {
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.ports.key];
    setState(() {
      _lastUpdatedAt = updatedAt;
    });
    _reloadPorts();
  }

  Future<void> _reloadPorts() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final serverId = provider.selectedServer?.id;
    if (serverId == null) {
      if (!mounted) return;
      setState(() => _ports = []);
      return;
    }
    final items = await provider.storageService.queryPorts(
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
    setState(() => _ports = items);
  }

  void refresh() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) {
      return;
    }
    setState(() => _isLoading = true);
    Future(() async {
      await provider.requestRefreshNow(
        RefreshScope.ports,
        reason: 'ports-refresh',
      );
      if (!mounted) return;
      _applyCache(provider);
      setState(() => _isLoading = false);
    });
  }

  Future<void> _killProcess(String pid) async {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final provider = Provider.of<AppProvider>(dialogContext, listen: false);
        final navigator = Navigator.of(dialogContext);
        return AlertDialog(
          title: const Text('确认终止'),
          content: Text('确定要终止PID $pid 的进程吗？'),
          actions: [
            TextButton(onPressed: navigator.pop, child: const Text('取消')),
            TextButton(
              onPressed: () async {
                setState(() => _isLoading = true);
                try {
                  await provider.killProcess(int.parse(pid), force: true);
                  await provider.requestRefreshNow(
                    RefreshScope.ports,
                    reason: 'ports-kill',
                  );
                  if (!mounted) {
                    return;
                  }
                  _applyCache(provider);
                } catch (_) {}
                setState(() => _isLoading = false);
                navigator.pop();
              },
              style: AppButtonStyles.textDanger(),
              child: const Text('终止'),
            ),
          ],
        );
      },
    );
  }

  List<PortInfo> get _filteredPorts {
    return _ports;
  }

  void _toggleSort(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = sortBy != 'port' && sortBy != 'pid';
      }
    });
    _reloadPorts();
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
          Expanded(child: _buildPortsTable()),
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
              decoration: AppFieldStyles.toolbarInput(hintText: '搜索端口或进程...'),
              onChanged: (text) {
                setState(() => _searchText = text);
                _reloadPorts();
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
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('刷新端口列表'),
        ),
      ],
    );
  }

  Widget _buildPortsTable() {
    if (_filteredPorts.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFe2e8f0)),
        ),
        child: const Center(
          child: Text(
            '暂无端口数据，或后台尚未采集完成',
            style: TextStyle(fontSize: 13, color: Color(0xFF6b7c93)),
          ),
        ),
      );
    }
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
                  label: '端口',
                  active: _sortBy == 'port',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('port'),
                ),
                SortHeaderCell(
                  label: '协议',
                  active: _sortBy == 'protocol',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('protocol'),
                ),
                SortHeaderCell(
                  label: '监听地址',
                  active: _sortBy == 'address',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('address'),
                ),
                SortHeaderCell(
                  label: 'PID',
                  active: _sortBy == 'pid',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('pid'),
                ),
                SortHeaderCell(
                  label: '进程名称',
                  active: _sortBy == 'processName',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('processName'),
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
              itemCount: _filteredPorts.length,
              itemBuilder: (context, index) {
                final port = _filteredPorts[index];
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
                          port.port,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Monospace',
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
                            color: port.protocol == 'TCP'
                                ? const Color(0xFFeff6ff)
                                : const Color(0xFFf0f4f8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            port.protocol,
                            style: TextStyle(
                              fontSize: 11,
                              color: port.protocol == 'TCP'
                                  ? const Color(0xFF2563eb)
                                  : const Color(0xFF6b7c93),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          port.address,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          port.pid,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          port.processName.isNotEmpty ? port.processName : '-',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: port.pid.isNotEmpty
                            ? GestureDetector(
                                onTap: () => _killProcess(port.pid),
                                child: const Icon(
                                  Icons.stop,
                                  color: Color(0xFFef4444),
                                  size: 18,
                                ),
                              )
                            : const SizedBox(),
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
