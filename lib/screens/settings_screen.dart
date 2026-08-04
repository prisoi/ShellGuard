import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../models/share_listener_config.dart';
import '../providers/app_provider.dart';
import '../widgets/app_button_styles.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Container(
      color: const Color(0xFFf0f4f8),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                _buildAppearanceCard(),
                const SizedBox(height: 24),
                _buildShareSection(context, provider),
                const SizedBox(height: 24),
                _buildLlmSection(context, provider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.settings, color: AppColors.textPrimary),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '系统设置',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '管理应用外观和 AI 助力所需的大模型接口',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppearanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '外观设置',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 14),
          Text(
            '当前版本先保留浅色模式，后续可继续扩展主题切换。',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildShareSection(BuildContext context, AppProvider provider) {
    final config = provider.shareListenerConfig;
    final running = provider.isShareListenerRunning;
    final runtimeError = provider.shareListenerError;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '共享侦听',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '让其他 ShellGuard 通过本机端口访问已分享的服务器资源',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showShareListenerDialog(context, provider),
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('配置侦听'),
                style: AppButtonStyles.primary(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildShareMetaCard(
                '当前状态',
                running ? '运行中' : (config.enabled ? '待启动' : '已关闭'),
                running ? const Color(0xFF10b981) : const Color(0xFF6b7c93),
              ),
              _buildShareMetaCard(
                '侦听端口',
                '${config.port}',
                const Color(0xFF2563eb),
              ),
              _buildShareMetaCard(
                '鉴权模式',
                config.authMode == ShareAuthMode.none ? '未启用' : 'Token 预留',
                const Color(0xFFd97706),
              ),
            ],
          ),
          if (runtimeError != null && runtimeError.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                '侦听启动异常：$runtimeError',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            '说明：当前版本默认不做鉴权，但数据结构和配置项已经预留好了后续升级入口。分享导出时不会暴露服务器真实 IP、用户名和密码。',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildShareMetaCard(String label, String value, Color color) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showShareListenerDialog(
    BuildContext context,
    AppProvider provider,
  ) async {
    final formKey = GlobalKey<FormState>();
    final portController = TextEditingController(
      text: '${provider.shareListenerConfig.port}',
    );
    final hostController = TextEditingController(text: '127.0.0.1');
    var enabled = provider.shareListenerConfig.enabled;
    var testMessage = '';
    var testSuccess = false;
    var testing = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('共享侦听配置'),
            content: SizedBox(
              width: 460,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: enabled,
                      onChanged: (value) => setState(() => enabled = value),
                      title: const Text('启用共享侦听'),
                      subtitle: const Text('开启后会在本机端口接收其他 ShellGuard 请求'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: portController,
                      keyboardType: TextInputType.number,
                      decoration: AppFieldStyles.outlined(labelText: '侦听端口'),
                      validator: (value) {
                        final port = int.tryParse(value?.trim() ?? '');
                        if (port == null || port < 1 || port > 65535) {
                          return '请输入有效端口';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: hostController,
                      decoration: AppFieldStyles.outlined(
                        labelText: '本地测试地址',
                        hintText: '例如 127.0.0.1',
                      ),
                    ),
                    if (testMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: testSuccess
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: testSuccess
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFFFECACA),
                          ),
                        ),
                        child: Text(
                          testMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: testSuccess
                                ? const Color(0xFF166534)
                                : const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      '当前认证模式固定为“未启用”，后续可在这里扩展 Token 或更完整的权限认证。',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: AppButtonStyles.text(),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: testing
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setState(() {
                          testing = true;
                          testMessage = '';
                        });
                        try {
                          final port = int.parse(portController.text.trim());
                          final host = hostController.text.trim().isEmpty
                              ? '127.0.0.1'
                              : hostController.text.trim();
                          final success = await provider.testShareEndpoint(
                            host: host,
                            port: port,
                          );
                          setState(() {
                            testSuccess = success;
                            testMessage = success
                                ? '探活成功：已连通 http://$host:$port/health'
                                : '探活失败：未收到正常响应';
                          });
                        } catch (error) {
                          setState(() {
                            testSuccess = false;
                            testMessage = error.toString();
                          });
                        } finally {
                          setState(() => testing = false);
                        }
                      },
                style: AppButtonStyles.subtle(),
                child: testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('本地探活'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) {
                    return;
                  }
                  final port = int.parse(portController.text.trim());
                  final nextConfig = provider.shareListenerConfig.copyWith(
                    enabled: enabled,
                    port: port,
                  );
                  await provider.updateShareListenerConfig(nextConfig);
                  if (enabled) {
                    await provider.restartShareListener(port: port);
                  } else {
                    await provider.setShareListenerEnabled(false);
                  }
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                style: AppButtonStyles.primary(),
                child: const Text('保存配置'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLlmSection(BuildContext context, AppProvider provider) {
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LLM 模型管理',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '配置 AI 助力使用的 OpenAI 兼容模型接口',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showProviderDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加模型'),
                style: AppButtonStyles.primary(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (provider.llmProviders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                '还没有可用的 LLM 配置，请先添加一个模型供应商。',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            )
          else
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: provider.llmProviders.map((item) {
                return _buildProviderCard(context, provider, item);
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(
    BuildContext context,
    AppProvider provider,
    LlmProviderConfig config,
  ) {
    final isDefault = config.isDefault;
    return SizedBox(
      width: 420,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDefault ? AppColors.primary : AppColors.border,
            width: isDefault ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFeff6ff),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.hub_outlined, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        config.model,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFeff6ff),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '默认',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _buildMeta('API Base URL', config.baseUrl),
            const SizedBox(height: 10),
            _buildMeta('API Key', config.maskedApiKey),
            const SizedBox(height: 10),
            _buildMeta('最大 Tokens', '${config.maxTokens}'),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => _showProviderDialog(context, existing: config),
                  style: AppButtonStyles.text(),
                  child: const Text('编辑'),
                ),
                const Spacer(),
                if (!config.isDefault)
                  TextButton(
                    onPressed: () async {
                      await provider.saveLlmProvider(config.copyWith(isDefault: true));
                    },
                    style: AppButtonStyles.text(),
                    child: const Text('设为默认'),
                  ),
                TextButton(
                  onPressed: () async {
                    await provider.deleteLlmProvider(config.id);
                  },
                  style: AppButtonStyles.textDanger(),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeta(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showProviderDialog(
    BuildContext context, {
    LlmProviderConfig? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LlmProviderDialog(existing: existing),
    );
  }
}

class _LlmProviderDialog extends StatefulWidget {
  final LlmProviderConfig? existing;

  const _LlmProviderDialog({this.existing});

  @override
  State<_LlmProviderDialog> createState() => _LlmProviderDialogState();
}

class _LlmProviderDialogState extends State<_LlmProviderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _maxTokensController;
  bool _enabled = true;
  bool _isDefault = false;
  bool _testing = false;
  String _testMessage = '';
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _baseUrlController = TextEditingController(
      text: existing?.baseUrl ?? 'https://api.openai.com/v1',
    );
    _apiKeyController = TextEditingController(text: existing?.apiKey ?? '');
    _modelController = TextEditingController(text: existing?.model ?? 'gpt-4o-mini');
    _maxTokensController = TextEditingController(
      text: '${existing?.maxTokens ?? 4096}',
    );
    _enabled = existing?.enabled ?? true;
    _isDefault = existing?.isDefault ?? widget.existing == null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? '添加 LLM 供应商' : '编辑 LLM 供应商',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '配置大模型接口信息，用于 AI 助力功能',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              _buildField('供应商名称', _nameController),
              const SizedBox(height: 14),
              _buildField('API Base URL', _baseUrlController),
              const SizedBox(height: 14),
              _buildField('API Key', _apiKeyController, obscureText: true),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _buildField('默认模型', _modelController)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      '最大 Tokens',
                      _maxTokensController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '启用此配置',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
              SwitchListTile(
                value: _isDefault,
                onChanged: (value) => setState(() => _isDefault = value),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '设为默认模型',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
              if (_testMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testSuccess
                        ? const Color(0xFFecfdf5)
                        : const Color(0xFFfef2f2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _testSuccess
                          ? const Color(0xFF86efac)
                          : const Color(0xFFfecaca),
                    ),
                  ),
                  child: Text(
                    _testMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: _testSuccess
                          ? const Color(0xFF166534)
                          : const Color(0xFF991b1b),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: AppButtonStyles.text(),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _testing ? null : _testConnection,
                    style: AppButtonStyles.subtle(),
                    child: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('测试连接'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    style: AppButtonStyles.primary(),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: AppFieldStyles.outlined(labelText: label),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '$label不能为空';
        }
        if (label == 'API Base URL') {
          final uri = Uri.tryParse(value.trim());
          if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
            return '请输入有效的 URL';
          }
        }
        return null;
      },
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _testing = true;
      _testMessage = '';
    });

    final provider = Provider.of<AppProvider>(context, listen: false);
    final config = _buildConfig();
    final result = await provider.testLlmProvider(config);
    if (!mounted) {
      return;
    }
    setState(() {
      _testing = false;
      _testSuccess = result.success;
      _testMessage = result.success
          ? '${result.message}，延迟 ${result.latencyMs ?? 0}ms'
          : result.message;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final provider = Provider.of<AppProvider>(context, listen: false);
    await provider.saveLlmProvider(_buildConfig());
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  LlmProviderConfig _buildConfig() {
    return LlmProviderConfig(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      maxTokens: int.tryParse(_maxTokensController.text.trim()) ?? 4096,
      enabled: _enabled,
      isDefault: _isDefault,
    );
  }
}
