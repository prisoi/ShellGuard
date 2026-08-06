import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/remote_control_models.dart';
import '../models/share_listener_config.dart';
import '../providers/app_provider.dart';
import '../widgets/app_button_styles.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  bool _didScheduleRefresh = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    if (!_didScheduleRefresh) {
      _didScheduleRefresh = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        provider.refreshRemoteControlState();
      });
    }
    return Container(
      color: const Color(0xFFF4F7FB),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '远程控制',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '管理共享侦听、access-token 与远程访问审计。当前免费版先做 token 校验与完整本地审计，为后续收费版的审批与加密鉴权预留结构。',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                _ShareListenerCard(provider: provider),
                const SizedBox(height: 20),
                _AccessTokenCard(provider: provider),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareListenerCard extends StatelessWidget {
  final AppProvider provider;

  const _ShareListenerCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final config = provider.shareListenerConfig;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '共享侦听',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showConfigDialog(context, provider),
                style: AppButtonStyles.primary(),
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('配置'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MetaChip(
                label: '状态',
                value: provider.isShareListenerRunning ? '运行中' : '已停止',
              ),
              _MetaChip(label: '端口', value: '${config.port}'),
              _MetaChip(
                label: '鉴权',
                value: config.authMode == ShareAuthMode.token ? 'Token' : '未启用',
              ),
            ],
          ),
          if ((provider.shareListenerError ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '最近异常：${provider.shareListenerError}',
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showConfigDialog(BuildContext context, AppProvider provider) async {
    final controller = TextEditingController(text: '${provider.shareListenerConfig.port}');
    var enabled = provider.shareListenerConfig.enabled;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('共享侦听配置'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                  title: const Text('启用共享侦听'),
                  subtitle: const Text('免费版默认启用 token 校验'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: AppFieldStyles.outlined(labelText: '端口'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                final port = int.tryParse(controller.text.trim()) ?? 8848;
                await provider.updateShareListenerConfig(
                  ShareListenerConfig(
                    enabled: enabled,
                    port: port,
                    authMode: ShareAuthMode.token,
                    tokenHint: 'access-token',
                  ),
                );
                if (enabled) {
                  await provider.restartShareListener(port: port);
                } else {
                  await provider.setShareListenerEnabled(false);
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessTokenCard extends StatelessWidget {
  final AppProvider provider;

  const _AccessTokenCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Access-Token 列表',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => provider.refreshRemoteControlState(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('刷新'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: provider.canCreateAccessToken
                    ? () => _showCreateDialog(context, provider)
                    : null,
                style: AppButtonStyles.primary(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建 Token'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '免费版同时最多 ${provider.maxConcurrentAccessTokenCount} 个生效中的 token，单个 token 最长有效期 ${provider.maxAccessTokenLifetime.inHours} 小时。',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          if (provider.accessTokens.isEmpty)
            const Text(
              '还没有 access-token。创建后可用于共享组导入验证和远程访问。',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          else
            ...provider.accessTokens.map(
              (token) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            token.note.isEmpty ? '未备注 Token' : token.note,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(token.maskedValue, style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            '到期时间：${token.expiresAt.toLocal()}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _MetaChip(
                      label: '状态',
                      value: token.isExpired
                          ? '已过期'
                          : token.isRevoked
                              ? '已失效'
                              : '生效中',
                    ),
                    const SizedBox(width: 8),
                    _MetaChip(label: '连接次数', value: '${token.connectionCount}'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _showAuditDialog(context, provider, token),
                      child: const Text('审计'),
                    ),
                    TextButton(
                      onPressed: token.isExpired
                          ? null
                          : () async {
                              try {
                                await provider.setAccessTokenRevoked(
                                  token.id,
                                  !token.isRevoked,
                                );
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                                );
                              }
                            },
                      child: Text(token.isRevoked ? '生效' : '失效'),
                    ),
                    TextButton(
                      onPressed: () => _confirmDeleteToken(context, provider, token),
                      style: AppButtonStyles.textDanger(),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, AppProvider provider) async {
    final noteController = TextEditingController();
    final expiresAt = DateTime.now().add(provider.maxAccessTokenLifetime);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('新建 Access-Token'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: noteController,
                  decoration: AppFieldStyles.outlined(labelText: '备注'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('失效时间'),
                  subtitle: Text(
                    '${expiresAt.toLocal()}（免费版固定 ${provider.maxAccessTokenLifetime.inHours} 小时）',
                  ),
                  trailing: const Icon(Icons.event),
                  onTap: null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final token = await provider.createAccessToken(
                    note: noteController.text.trim(),
                    expiresAt: expiresAt,
                  );
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.of(context).pop();
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Token 已生成'),
                      content: SelectableText(token.tokenValue),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('知道了'),
                        ),
                      ],
                    ),
                  );
                } catch (error) {
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                  );
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAuditDialog(
    BuildContext context,
    AppProvider provider,
    AccessTokenRecord token,
  ) async {
    final logs = await provider.loadRemoteAuditLogs(accessTokenId: token.id);
    final sortedLogs = [...logs]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('审计记录 - ${token.note.isEmpty ? token.maskedValue : token.note}'),
        content: SizedBox(
          width: 760,
          height: 420,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _exportAuditCsv(context, token, logs),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('导出 CSV'),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: sortedLogs.isEmpty
                    ? const Center(child: Text('暂无审计记录'))
                    : _buildAuditTimeline(sortedLogs),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAuditCsv(
    BuildContext context,
    AccessTokenRecord token,
    List<RemoteAuditRecord> logs,
  ) async {
    final safeNote = _sanitizeFileNameSegment(
      token.note.isEmpty ? '未备注' : token.note,
    );
    final location = await getSaveLocation(
      suggestedName: 'remote_audit_${safeNote}_${token.id}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (location == null) {
      return;
    }
    final sortedLogs = [...logs]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final buffer = StringBuffer()
      ..writeln(
        'group_label,session_id,connection_id,category,action,title,server_name,group_name,source_host,source_label,summary,detail,success,created_at',
      );
    for (final log in sortedLogs) {
      buffer.writeln(
        [
          _escapeCsv(log.auditGroupLabel),
          _escapeCsv(log.sessionId),
          _escapeCsv(log.connectionId),
          log.category.name,
          log.action,
          _escapeCsv(log.timelineTitle),
          _escapeCsv(log.displayServerName),
          _escapeCsv(log.displayGroupName),
          _escapeCsv(log.sourceHost),
          _escapeCsv(log.sourceLabel),
          _escapeCsv(log.summary),
          _escapeCsv(log.normalizedDetail),
          log.success ? '1' : '0',
          log.createdAt.toIso8601String(),
        ].join(','),
      );
    }
    final file = XFile.fromData(
      utf8.encode(buffer.toString()),
      mimeType: 'text/csv',
      name: location.path,
    );
    await file.saveTo(location.path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('审计记录已导出到 ${location.path}')),
      );
    }
  }

  String _escapeCsv(String value) {
    final normalized = value.replaceAll('"', '""');
    return '"$normalized"';
  }

  String _sanitizeFileNameSegment(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'token' : sanitized;
  }

  Future<void> _confirmDeleteToken(
    BuildContext context,
    AppProvider provider,
    AccessTokenRecord token,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除 Token'),
        content: Text(
          '删除后将同时丢失该 Token 的所有操作记录、AI 助力记录和 SSH 审计记录。\n\n确定删除“${token.note.isEmpty ? token.maskedValue : token.note}”吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: AppButtonStyles.textDanger(),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.deleteAccessToken(token.id);
    }
  }

  Widget _buildAuditTimeline(List<RemoteAuditRecord> logs) {
    final items = <Widget>[];
    var index = 0;
    while (index < logs.length) {
      final item = logs[index];
      final canGroupBySession =
          (item.category == RemoteAuditCategory.ai ||
              item.category == RemoteAuditCategory.terminal) &&
          item.sessionId.isNotEmpty;
      if (canGroupBySession) {
        final sessionId = item.sessionId;
        final group = <RemoteAuditRecord>[];
        while (index < logs.length &&
            logs[index].category == item.category &&
            logs[index].sessionId == sessionId) {
          group.add(logs[index]);
          index++;
        }
        items.add(_buildSessionAuditGroup(group));
      } else {
        items.add(_buildAuditTile(item));
        index++;
      }
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) => items[index],
    );
  }

  Widget _buildSessionAuditGroup(List<RemoteAuditRecord> logs) {
    final first = logs.first;
    final title = first.category == RemoteAuditCategory.ai ? 'AI助力会话' : 'SSH终端会话';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title · ${first.displayServerName.isEmpty ? first.summary : first.displayServerName}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${logs.first.createdAt.toLocal()} - ${logs.last.createdAt.toLocal()}',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          if (_buildContextWrap(first) != null) ...[
            const SizedBox(height: 8),
            _buildContextWrap(first)!,
          ],
          const SizedBox(height: 10),
          ...logs.map(_buildAuditTile),
        ],
      ),
    );
  }

  Widget _buildAuditTile(RemoteAuditRecord item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildCategoryChip(item.auditGroupLabel),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.timelineTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                item.createdAt.toLocal().toString(),
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.summary,
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
          ),
          if (_buildContextWrap(item) != null) ...[
            const SizedBox(height: 8),
            _buildContextWrap(item)!,
          ],
          if (item.normalizedDetail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.normalizedDetail,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildContextWrap(RemoteAuditRecord item) {
    final chips = <Widget>[
      if (item.displayServerName.isNotEmpty)
        _buildInfoChip(Icons.dns_outlined, item.displayServerName),
      if (item.displayGroupName.isNotEmpty)
        _buildInfoChip(Icons.folder_shared_outlined, item.displayGroupName),
      if (item.displaySource.isNotEmpty)
        _buildInfoChip(Icons.lan_outlined, item.displaySource),
      if (item.connectionId.isNotEmpty)
        _buildInfoChip(Icons.link_outlined, item.connectionId),
    ];
    if (chips.isEmpty) {
      return null;
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
