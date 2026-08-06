import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/refresh_scope.dart';
import '../models/query_options.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import '../widgets/app_button_styles.dart';
import '../widgets/adaptive_page_layout.dart';
import '../widgets/sort_header_cell.dart';

class FirewallScreen extends StatefulWidget {
  const FirewallScreen({super.key});

  @override
  State<FirewallScreen> createState() => FirewallScreenState();
}

class FirewallScreenState extends State<FirewallScreen> {
  List<FirewallRule> _rules = [];
  bool _isEnabled = false;
  bool _isLoading = false;
  final _portController = TextEditingController();
  final _sourceController = TextEditingController();
  final _searchController = TextEditingController();
  String _selectedProtocol = 'TCP';
  String _selectedAction = 'ALLOW';
  String _searchText = '';
  String _sortBy = 'id';
  bool _sortAscending = true;
  String? _lastServerId;
  String? _lastUpdatedAt;

  Future<bool> _ensureFirewallSession(AppProvider provider) {
    return provider.ensureTerminalConnection();
  }

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
    final serverId = provider.selectedServer?.id;
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.firewall.key];
    if (_lastServerId != serverId) {
      _lastServerId = serverId;
      _lastUpdatedAt = null;
      _syncFromCache();
      provider.onPageEnter(RefreshScope.firewall);
    } else if (updatedAt != null && updatedAt != _lastUpdatedAt) {
      _syncFromCache();
    }
  }

  void _syncFromCache() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.currentCache == null) {
      setState(() {
        _rules = [];
        _isEnabled = false;
      });
      return;
    }
    setState(() {
      _rules = provider.currentCache!.firewallRules ?? [];
      _isEnabled = provider.currentCache!.firewallEnabled ?? false;
      _lastUpdatedAt =
          provider.currentCache!.scopeUpdatedAt[RefreshScope.firewall.key];
    });
    _reloadRules();
  }

  Future<void> _reloadRules() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final serverId = provider.selectedServer?.id;
    if (serverId == null) {
      if (!mounted) return;
      setState(() => _rules = []);
      return;
    }
    final items = await provider.storageService.queryFirewallRules(
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
    setState(() => _rules = items);
  }

  void _toggleSort(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = sortBy == 'id' || sortBy == 'port';
      }
    });
    _reloadRules();
  }

  Future<void> refresh() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    setState(() => _isLoading = true);
    await provider.requestRefreshNow(
      RefreshScope.firewall,
      reason: 'firewall-refresh',
    );
    _syncFromCache();
    setState(() => _isLoading = false);
  }

  Future<void> _toggleFirewall(bool enable) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;

    setState(() => _isLoading = true);
    try {
      final ready = await _ensureFirewallSession(provider);
      if (!ready) {
        return;
      }
      await provider.manageFirewallSelected(
        action: enable ? 'enable' : 'disable',
      );
      await provider.requestRefreshNow(
        RefreshScope.firewall,
        reason: 'firewall-toggle',
      );
      _syncFromCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('防火墙操作失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addRule() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final port = _portController.text.trim();
    final source = _sourceController.text.trim();
    if (provider.selectedServer == null || (port.isEmpty && source.isEmpty)) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final ready = await _ensureFirewallSession(provider);
      if (!ready) {
        return;
      }
      await provider.manageFirewallSelected(
        action: _selectedAction.toLowerCase(),
        port: port.isEmpty ? null : port,
        protocol: _selectedProtocol.toLowerCase(),
        source: source.isEmpty ? null : source,
      );
      _portController.clear();
      _sourceController.clear();
      await provider.requestRefreshNow(
        RefreshScope.firewall,
        reason: 'firewall-add-rule',
      );
      _syncFromCache();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('规则已添加')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('添加规则失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteRule(FirewallRule rule) async {
    final summary = [
      if (rule.port != null && rule.port!.isNotEmpty)
        '${rule.port}/${rule.protocol}',
      if (rule.source != null && rule.source!.isNotEmpty) '来源 ${rule.source}',
    ].join('，');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认删除规则'),
          content: Text(
            summary.isEmpty
                ? '确定要删除编号 ${rule.id} 的防火墙规则吗？'
                : '确定要删除编号 ${rule.id} 的防火墙规则吗？\n$summary',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: AppButtonStyles.text(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: AppButtonStyles.textDanger(),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _deleteRuleConfirmed(rule);
    }
  }

  Future<void> _deleteRuleConfirmed(FirewallRule rule) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    setState(() => _isLoading = true);
    try {
      final ready = await _ensureFirewallSession(provider);
      if (!ready) {
        return;
      }
      try {
        await provider.manageFirewallSelected(
          action: 'delete',
          ruleNumber: rule.id,
          ruleAction: rule.action,
          port: rule.port,
          protocol: rule.protocol == 'ALL' ? null : rule.protocol.toLowerCase(),
          source: rule.source,
        );
      } catch (_) {
        await provider.manageFirewallSelected(
          action: 'delete',
          ruleAction: rule.action,
          port: rule.port,
          protocol: rule.protocol == 'ALL' ? null : rule.protocol.toLowerCase(),
          source: rule.source,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _rules = _rules.where((item) => item.id != rule.id).toList();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('规则已删除，正在同步最新状态')));
      unawaited(_refreshFirewallInBackground(provider));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除规则失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshFirewallInBackground(AppProvider provider) async {
    try {
      await provider.requestRefreshNow(
        RefreshScope.firewall,
        reason: 'firewall-delete-rule',
      );
      if (mounted) {
        _syncFromCache();
      }
    } catch (_) {}
  }

  Future<void> _resetFirewall() async {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final provider = Provider.of<AppProvider>(dialogContext, listen: false);
        final navigator = Navigator.of(dialogContext);
        return AlertDialog(
          title: const Text('确认重置'),
          content: const Text('确定要清空所有防火墙规则吗？'),
          actions: [
            TextButton(onPressed: navigator.pop, child: const Text('取消')),
            TextButton(
              onPressed: () async {
                setState(() => _isLoading = true);
                try {
                  final ready = await _ensureFirewallSession(provider);
                  if (!ready) {
                    return;
                  }
                  await provider.manageFirewallSelected(action: 'reset');
                  await provider.requestRefreshNow(
                    RefreshScope.firewall,
                    reason: 'firewall-reset',
                  );
                  _syncFromCache();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('重置防火墙失败: $e')));
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                  navigator.pop();
                }
              },
              style: AppButtonStyles.textDanger(),
              child: const Text('重置'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return AdaptivePageLayout(
      estimatedReservedHeight: 290,
      minBodyHeight: 220,
      header: [
        _buildTopBar(provider),
        const SizedBox(height: 16),
        _buildFirewallToggle(provider),
        const SizedBox(height: 16),
        _buildAddRuleForm(provider),
        const SizedBox(height: 16),
      ],
      body: _buildRulesTable(),
      footer: [const SizedBox(height: 16), _buildResetButton()],
    );
  }

  Widget _buildTopBar(AppProvider provider) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            '防火墙规则支持手动刷新与实时开关操作',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7C93),
              fontWeight: FontWeight.w500,
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
              : const Text('刷新防火墙'),
        ),
      ],
    );
  }

  Widget _buildFirewallToggle(AppProvider provider) {
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.firewall.key];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield, size: 24, color: Color(0xFF2563eb)),
          const SizedBox(width: 16),
          const Text(
            '防火墙总开关',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Switch(
            value: _isEnabled,
            onChanged: provider.selectedServer != null && !_isLoading
                ? (value) => _toggleFirewall(value)
                : null,
            activeThumbColor: const Color(0xFF10b981),
            inactiveTrackColor: const Color(0xFFe2e8f0),
          ),
          const SizedBox(width: 16),
          Text(
            _isEnabled ? '开启' : '关闭',
            style: TextStyle(
              fontSize: 13,
              color: _isEnabled
                  ? const Color(0xFF10b981)
                  : const Color(0xFF6b7c93),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            updatedAt == null ? '等待后台采集' : '更新于 ${_formatTimestamp(updatedAt)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddRuleForm(AppProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            '添加规则:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          AppControlShell(
            width: 110,
            backgroundColor: const Color(0xFFf0f4f8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedAction,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'ALLOW', child: Text('放行')),
                  DropdownMenuItem(value: 'DENY', child: Text('阻断')),
                ],
                onChanged: (value) => setState(() => _selectedAction = value!),
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: TextField(
              controller: _portController,
              decoration: AppFieldStyles.outlined(hintText: '端口号'),
              keyboardType: TextInputType.number,
            ),
          ),
          SizedBox(
            width: 160,
            child: TextField(
              controller: _sourceController,
              decoration: AppFieldStyles.outlined(hintText: '来源 IP/CIDR(可选)'),
            ),
          ),
          AppControlShell(
            width: 110,
            backgroundColor: const Color(0xFFf0f4f8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProtocol,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'TCP', child: Text('TCP')),
                  DropdownMenuItem(value: 'UDP', child: Text('UDP')),
                ],
                onChanged: (value) =>
                    setState(() => _selectedProtocol = value!),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: provider.selectedServer != null && !_isLoading
                ? _addRule
                : null,
            style: AppButtonStyles.primary(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text('添加规则'),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              decoration: AppFieldStyles.outlined(hintText: '搜索规则...'),
              onChanged: (value) {
                setState(() => _searchText = value);
                _reloadRules();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesTable() {
    if (_rules.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFe2e8f0)),
        ),
        child: const Center(
          child: Text(
            '当前暂无防火墙规则，或后台尚未采集完成',
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
                  label: 'ID',
                  active: _sortBy == 'id',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('id'),
                ),
                SortHeaderCell(
                  label: '动作',
                  active: _sortBy == 'action',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('action'),
                ),
                SortHeaderCell(
                  label: '协议',
                  active: _sortBy == 'protocol',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('protocol'),
                ),
                SortHeaderCell(
                  label: '端口',
                  active: _sortBy == 'port',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('port'),
                ),
                SortHeaderCell(
                  label: '来源',
                  active: _sortBy == 'source',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('source'),
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
              itemCount: _rules.length,
              itemBuilder: (context, index) {
                final rule = _rules[index];
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
                          rule.id,
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
                            color: rule.action == 'ALLOW'
                                ? const Color(0xFFecfdf5)
                                : const Color(0xFFfef2f2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            rule.action,
                            style: TextStyle(
                              fontSize: 11,
                              color: rule.action == 'ALLOW'
                                  ? const Color(0xFF10b981)
                                  : const Color(0xFFef4444),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rule.protocol,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rule.port ?? '-',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rule.source ?? '-',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AppIconActionButton(
                            icon: Icons.delete_outline,
                            tooltip: '删除规则',
                            onPressed: _isLoading ? null : () => _deleteRule(rule),
                            foregroundColor: const Color(0xFFef4444),
                            backgroundColor: const Color(0xFFfef2f2),
                          ),
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

  Widget _buildResetButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Row(
        children: [
          const Text(
            '支持按来源 IP/CIDR 限制端口，例如允许 10.147.18.0/24 访问 8888/TCP。',
            style: TextStyle(fontSize: 11, color: Color(0xFF6b7c93)),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _isLoading ? null : _resetFirewall,
            style: AppButtonStyles.danger(),
            child: const Text('重置防火墙'),
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
