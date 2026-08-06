import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import './app_button_styles.dart';

class TopBar extends StatelessWidget {
  final String? title;
  final Function()? onConnect;

  const TopBar({super.key, this.title, this.onConnect});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Container(
      height: 52,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            title ?? 'ShellGuard',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1a2332),
            ),
          ),
          const Spacer(),
          _buildServerSelector(provider, context),
          const SizedBox(width: 12),
          _buildAddServerButton(provider, context),
          const SizedBox(width: 16),
          _buildConnectButton(provider, context),
          const SizedBox(width: 12),
          _buildUserMenu(),
        ],
      ),
    );
  }

  Widget _buildServerSelector(AppProvider provider, BuildContext context) {
    final options = provider.serverSelectionOptions;
    if (options.isEmpty) {
      return SizedBox(
        width: 260,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFfef3c7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFfbbf24)),
          ),
          child: const Text(
            '暂无服务器，请添加',
            style: TextStyle(fontSize: 12, color: Color(0xFF92400e)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return AppControlShell(
      width: 320,
      backgroundColor: const Color(0xFFf0f4f8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.any((item) => item.id == provider.selectedServer?.id)
              ? provider.selectedServer?.id
              : null,
          isExpanded: true,
          items: options.map((option) {
            return DropdownMenuItem<String>(
              value: option.id,
              child: Row(
                children: [
                  Icon(
                    option.isOnline ? Icons.check_circle : Icons.circle,
                    color: option.isOnline
                        ? const Color(0xFF10b981)
                        : const Color(0xFF6b7c93),
                    size: 12,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    option.isLocal ? Icons.computer_outlined : Icons.hub_outlined,
                    size: 14,
                    color: option.isLocal
                        ? const Color(0xFF2563eb)
                        : const Color(0xFFd97706),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    option.title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1a2332),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      option.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6b7c93),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (serverId) {
            if (serverId != null) {
              provider.selectServerById(serverId);
            }
          },
          selectedItemBuilder: (context) {
            return options.map((option) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Icon(
                      option.isOnline ? Icons.check_circle : Icons.circle,
                      color: option.isOnline
                          ? const Color(0xFF10b981)
                          : const Color(0xFF6b7c93),
                      size: 12,
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      option.isLocal ? Icons.computer_outlined : Icons.hub_outlined,
                      size: 14,
                      color: option.isLocal
                          ? const Color(0xFF2563eb)
                          : const Color(0xFFd97706),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${option.title} (${option.subtitle})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1a2332),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          style: const TextStyle(fontSize: 12),
          icon: const Icon(Icons.arrow_drop_down, size: 16),
        ),
      ),
    );
  }

  Widget _buildAddServerButton(AppProvider provider, BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        if (!provider.canAddMoreServers) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                '个人免费版最多支持 ${provider.maxManagedServerCount} 台总资源（本地 ${provider.servers.length} 台，共享 ${provider.importedSharedServerCount} 台）',
              ),
            ),
          );
          return;
        }
        showDialog(
          context: context,
          builder: (context) => _ServerManagementDialog(provider: provider),
        );
      },
      icon: const Icon(Icons.add, size: 14),
      label: const Text('添加服务器'),
      style:
          AppButtonStyles.primary(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ).copyWith(
            elevation: const WidgetStatePropertyAll(0),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
    );
  }

  Widget _buildConnectButton(AppProvider provider, BuildContext context) {
    final connected = provider.isConnected;
    return ElevatedButton(
      onPressed: provider.selectedServer == null || provider.isLoading
          ? null
          : onConnect,
      style: connected
          ? AppButtonStyles.success(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            )
          : AppButtonStyles.primary(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
      child: Row(
        children: [
          Icon(connected ? Icons.wifi : Icons.wifi_off, size: 14),
          const SizedBox(width: 6),
          Text(
            connected ? '已连接' : '连接',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMenu() {
    return PopupMenuButton<int>(
      tooltip: '账户菜单',
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 10,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 280),
      padding: EdgeInsets.zero,
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: _buildUserMenuHeader(),
        ),
        const PopupMenuDivider(height: 1),
        _buildDisabledMenuItem(
          label: '管理账号',
          trailingIcon: Icons.open_in_new_rounded,
        ),
        _buildDisabledMenuItem(
          label: '消息',
          trailing: _buildMessageBadge(),
        ),
        const PopupMenuDivider(height: 1),
        _buildDisabledMenuItem(
          label: '主题',
          trailingText: '亮色',
          trailingIcon: Icons.chevron_right_rounded,
        ),
        _buildDisabledMenuItem(label: '检查更新'),
        _buildDisabledMenuItem(
          label: '帮助文档',
          trailingIcon: Icons.open_in_new_rounded,
        ),
        _buildDisabledMenuItem(
          label: '联系我们',
          trailingIcon: Icons.open_in_new_rounded,
        ),
        _buildDisabledMenuItem(label: '报告问题'),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<int>(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            alignment: Alignment.center,
            child: const Text(
              '前去注册',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
      child: _buildUserAvatarTrigger(),
    );
  }

  PopupMenuItem<int> _buildDisabledMenuItem({
    required String label,
    IconData? trailingIcon,
    String? trailingText,
    Widget? trailing,
  }) {
    return PopupMenuItem<int>(
      enabled: false,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ...(trailing == null ? const <Widget>[] : <Widget>[trailing]),
          if (trailingText != null) ...[
            Text(
              trailingText,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (trailingIcon != null) const SizedBox(width: 4),
          ],
          if (trailingIcon != null)
            Icon(trailingIcon, size: 18, color: const Color(0xFF94A3B8)),
        ],
      ),
    );
  }

  Widget _buildUserMenuHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Icon(
            Icons.person_outline_rounded,
            color: Color(0xFF94A3B8),
            size: 26,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '未登录',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A2332),
                ),
              ),
              SizedBox(height: 4),
              Text(
                '登录后可同步账号与订阅状态',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Text(
            '未注册',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBadge() {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFE2E8F0),
        shape: BoxShape.circle,
      ),
      child: const Text(
        '2',
        style: TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildUserAvatarTrigger() {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Center(
            child: Icon(
              Icons.person_search_rounded,
              color: Color(0xFF64748B),
              size: 20,
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerManagementDialog extends StatefulWidget {
  final AppProvider provider;

  const _ServerManagementDialog({required this.provider});

  @override
  _ServerManagementDialogState createState() => _ServerManagementDialogState();
}

class _ServerManagementDialogState extends State<_ServerManagementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isTesting = false;
  bool _isSaving = false;
  bool _testSuccess = false;
  String _testMessage = '';

  @override
  void initState() {
    super.initState();
    _portController.text = '22';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testSuccess = false;
      _testMessage = '正在测试连接...';
    });

    final testServer = Server(
      id: 'test',
      name: _nameController.text,
      ip: _ipController.text,
      port: int.tryParse(_portController.text) ?? 22,
      username: _usernameController.text,
      password: _passwordController.text,
    );

    final sshManager = widget.provider.sshManager;
    final success = await sshManager.connect(testServer);

    if (success) {
      String detectedOs = '';
      try {
        final systemInfo = await sshManager.getSystemInfo();
        detectedOs = systemInfo.osDisplayLabel;
      } catch (_) {}
      sshManager.disconnect();
      setState(() {
        _isTesting = false;
        _testSuccess = true;
        _testMessage = detectedOs.isEmpty ? '连接成功！' : '连接成功，已识别系统：$detectedOs';
      });
      return;
    }

    setState(() {
      _isTesting = false;
      _testSuccess = false;
      _testMessage = sshManager.errorMessage ?? '连接失败';
    });
  }

  Future<void> _saveServer() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _testSuccess = false;
      _testMessage = '';
    });

    final server = Server(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      ip: _ipController.text,
      port: int.tryParse(_portController.text) ?? 22,
      username: _usernameController.text,
      password: _passwordController.text,
      tags: _noteController.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
    );

    try {
      await widget.provider.addServer(server);
      if (!mounted) {
        return;
      }
      unawaited(widget.provider.selectServer(server));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _testSuccess = false;
        _testMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '添加服务器',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1a2332),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 20),
                _buildFormField(
                  '服务器名称',
                  _nameController,
                  Icons.computer,
                  required: true,
                ),
                const SizedBox(height: 16),
                _buildFormField(
                  'IP地址',
                  _ipController,
                  Icons.network_check,
                  required: true,
                ),
                const SizedBox(height: 16),
                _buildFormField(
                  'SSH端口',
                  _portController,
                  Icons.router,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                _buildFormField(
                  '用户名',
                  _usernameController,
                  Icons.person,
                  required: true,
                ),
                const SizedBox(height: 16),
                _buildPasswordField(),
                const SizedBox(height: 16),
                _buildFormField('备注标签', _noteController, Icons.label),
                const SizedBox(height: 20),
                _buildTestResult(),
                const SizedBox(height: 16),
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: AppFieldStyles.outlined(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF6b7c93)),
      ),
      validator: (value) {
        if (required && (value == null || value.isEmpty)) {
          return '$label不能为空';
        }
        if (label == 'IP地址' && value != null && value.isNotEmpty) {
          final parts = value.split('.');
          if (parts.length != 4 ||
              parts.any((p) => int.tryParse(p) == null || int.parse(p) > 255)) {
            return '请输入有效的IP地址';
          }
        }
        if (label == 'SSH端口' && value != null && value.isNotEmpty) {
          final port = int.tryParse(value);
          if (port == null || port < 1 || port > 65535) {
            return '请输入有效的端口号(1-65535)';
          }
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: true,
      decoration: AppFieldStyles.outlined(
        labelText: '密码',
        prefixIcon: const Icon(Icons.lock, size: 18, color: Color(0xFF6b7c93)),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '密码不能为空';
        }
        return null;
      },
    );
  }

  Widget _buildTestResult() {
    if (_testMessage.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _testSuccess ? const Color(0xFFd1fae5) : const Color(0xFFfee2e2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _testSuccess
              ? const Color(0xFF10b981)
              : const Color(0xFFef4444),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _testSuccess ? Icons.check_circle : Icons.error,
            color: _testSuccess
                ? const Color(0xFF10b981)
                : const Color(0xFFef4444),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _testMessage,
              style: TextStyle(
                color: _testSuccess
                    ? const Color(0xFF065f46)
                    : const Color(0xFF991b1b),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: _isTesting || _isSaving ? null : () => Navigator.of(context).pop(),
            style:
                AppButtonStyles.text(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ).copyWith(
                  side: const WidgetStatePropertyAll(
                    BorderSide(color: AppColors.border),
                  ),
                ),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isTesting || _isSaving ? null : _testConnection,
            style: AppButtonStyles.warning(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _isTesting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text('测试连接', style: TextStyle(color: Colors.white)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isTesting || _isSaving ? null : () async => _saveServer(),
            style: AppButtonStyles.primary(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
