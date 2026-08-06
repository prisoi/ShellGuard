import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../providers/app_provider.dart';
import '../widgets/app_button_styles.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _promptController = TextEditingController();
  final Set<String> _collapsedStepIds = <String>{};
  String? _lastSessionId;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final activeSession = provider.activeAiSession;
    final messages = provider.activeAiMessages;
    final stepsByMessage = provider.activeAiStepsByMessage;
    final activeSessionId = provider.activeAiSessionId;
    if (_lastSessionId != activeSessionId) {
      _lastSessionId = activeSessionId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _promptController.clear();
      });
    }

    return Container(
      color: const Color(0xFFf8fafc),
      child: Row(
        children: [
          _buildLeftPanel(provider),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(provider),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 760),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (activeSession != null && messages.isNotEmpty) ...[
                                      if (activeSession.compressedContext.trim().isNotEmpty) ...[
                                        _buildCompressedContextCard(
                                          activeSession.compressedContext,
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                      ..._buildConversation(
                                        provider,
                                        messages,
                                        stepsByMessage,
                                      ),
                                    ] else
                                      _buildEmptyState(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildComposer(provider),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(AppProvider provider) {
    final server = provider.selectedServer;
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '目标服务器',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: server == null
                      ? const Text(
                          '请先在顶部选择服务器',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${server.name} (${server.ip})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: provider.isConnected
                                        ? AppColors.success
                                        : AppColors.textMuted,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  provider.isConnected ? '已连接' : '未连接',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: provider.isConnected
                                        ? AppColors.success
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              server.osDisplayLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            if ((server.packageManager?.trim().isNotEmpty ?? false) ||
                                (server.firewallBackend?.trim().isNotEmpty ?? false))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'pkg:${server.packageManager?.trim().isEmpty ?? true ? 'unknown' : server.packageManager} · '
                                  'fw:${server.firewallBackend?.trim().isEmpty ?? true ? 'unknown' : server.firewallBackend}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '历史会话',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '新建会话',
                      onPressed: provider.selectedServer == null
                          ? null
                          : () => provider.createAiSession(),
                      icon: const Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      splashRadius: 18,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (provider.aiSessions.isEmpty)
                  _buildEmptySessionTip(provider),
                ...provider.aiSessions.map((session) {
                  final selected = session.id == provider.activeAiSessionId;
                  return _buildHistorySessionCard(
                    context,
                    provider,
                    session,
                    selected: selected,
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(AppProvider provider) {
    final session = provider.activeAiSession;
    final canInterrupt = session != null &&
        (session.status == AiTaskStatus.running ||
            session.status == AiTaskStatus.waitingConfirm ||
            session.status == AiTaskStatus.analyzing);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary),
          const SizedBox(width: 8),
          const Text(
            'AI 助力',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: canInterrupt
                ? () => provider.interruptAiSession(session.id)
                : null,
            icon: const Icon(Icons.stop_circle_outlined, size: 16),
            label: const Text('中断执行'),
            style: AppButtonStyles.danger(),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildConversation(
    AppProvider provider,
    List<AiMessageRecord> messages,
    Map<String, List<AiStepRecord>> stepsByMessage,
  ) {
    final widgets = <Widget>[];
    for (final message in messages) {
      if (message.role == AiMessageRole.user) {
        widgets.add(_buildUserPrompt(message.content));
        widgets.add(const SizedBox(height: 16));
        continue;
      }
      if (message.role == AiMessageRole.summary) {
        widgets.add(_buildCompressedContextCard(message.content));
        widgets.add(const SizedBox(height: 16));
        continue;
      }

      widgets.add(
        _buildAnalysisCard(
          message.analysis,
          message.status,
          errorMessage: message.errorMessage,
        ),
      );
      final steps = stepsByMessage[message.id] ?? const <AiStepRecord>[];
      if (steps.isNotEmpty) {
        widgets.add(const SizedBox(height: 16));
        widgets.addAll(steps.map(_buildStepItem));
      }
      if (message.finalAnswer.trim().isNotEmpty) {
        widgets.add(const SizedBox(height: 16));
        widgets.add(_buildFinalAnswerCard(message.finalAnswer));
      }
      widgets.add(const SizedBox(height: 16));
    }
    if (widgets.isNotEmpty) {
      widgets.removeLast();
    }
    return widgets;
  }

  Widget _buildUserPrompt(String prompt) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          prompt,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            height: 1.6,
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisCard(
    String analysis,
    AiTaskStatus status, {
    String? errorMessage,
  }) {
    final title = switch (status) {
      AiTaskStatus.analyzing => '分析用户需求中...',
      AiTaskStatus.waitingConfirm => '等待风险确认',
      AiTaskStatus.running => '正在执行 AI 计划',
      AiTaskStatus.success => '执行完成',
      AiTaskStatus.failed => '执行失败',
      AiTaskStatus.interrupted => '任务已中断',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status == AiTaskStatus.failed
                ? (errorMessage?.trim().isNotEmpty == true
                    ? errorMessage!.trim()
                    : '任务执行失败，请检查模型配置、网络或 SSH 连接。')
                : analysis.isEmpty
                    ? '正在让 LLM 分析任务，请稍候...'
                    : analysis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompressedContextCard(String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFfffbeb),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '历史摘要',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(AiStepRecord step) {
    final isCollapsed = _collapsedStepIds.contains(step.id);
    final color = switch (step.status) {
      AiStepStatus.success => AppColors.success,
      AiStepStatus.failed => AppColors.danger,
      AiStepStatus.running => AppColors.primary,
      AiStepStatus.waitingConfirm => AppColors.warning,
      AiStepStatus.interrupted => AppColors.danger,
      AiStepStatus.skipped => AppColors.textMuted,
      AiStepStatus.pending => AppColors.border,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${step.orderIndex + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    if (isCollapsed) {
                      _collapsedStepIds.remove(step.id);
                    } else {
                      _collapsedStepIds.add(step.id);
                    }
                  });
                },
                icon: Icon(
                  isCollapsed ? Icons.expand_more : Icons.expand_less,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                tooltip: isCollapsed ? '展开结果' : '折叠结果',
                splashRadius: 18,
                visualDensity: VisualDensity.compact,
              ),
              _StepStatusBadge(step: step),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1a2332),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              step.command,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF67e8f9),
                fontFamily: 'Consolas',
              ),
            ),
          ),
          if (step.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              step.summary,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                height: 1.6,
              ),
            ),
          ],
          if (!isCollapsed) ...[
            if (step.output.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildOutputBox('输出', step.output, const Color(0xFFF8FAFC)),
            ],
            if (step.errorOutput.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildOutputBox('错误', step.errorOutput, const Color(0xFFfef2f2)),
            ],
          ],
          if (step.status == AiStepStatus.waitingConfirm) ...[
            const SizedBox(height: 12),
            _buildInlineRiskConfirm(step),
          ],
        ],
      ),
    );
  }

  Widget _buildInlineRiskConfirm(AiStepRecord step) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final sessionId = provider.activeAiSessionId;
    if (sessionId == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFfff7ed),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '此步骤需要你的确认',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9A3412),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '确认后将执行该命令；拒绝后会记录“用户拒绝执行”，并交给 LLM 继续判断。',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton(
                onPressed: () => provider.approveAiStep(
                  sessionId,
                  step.taskId,
                  step.id,
                  execute: true,
                ),
                style: AppButtonStyles.primary(),
                child: const Text('确认执行'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => provider.approveAiStep(
                  sessionId,
                  step.taskId,
                  step.id,
                  execute: false,
                ),
                child: const Text('拒绝执行'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinalAnswerCard(String finalAnswer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFecfdf5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最终回答',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF166534),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            finalAnswer,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputBox(String title, String content, Color backgroundColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content.trim(),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              fontFamily: 'Consolas',
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(AppProvider provider) {
    final isEmptyActiveSession = provider.activeAiSession == null ||
        provider.activeAiMessages.isEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              TextField(
                controller: _promptController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: isEmptyActiveSession
                      ? '输入内容即可创建第一个会话...'
                      : '继续追加你的需求...',
                  border: InputBorder.none,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      provider.defaultLlmProvider == null
                          ? '未配置 LLM，请先去系统设置添加模型'
                          : '当前模型：${provider.defaultLlmProvider!.name} / ${provider.defaultLlmProvider!.model}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final prompt = _promptController.text.trim();
                      if (prompt.isEmpty) {
                        return;
                      }
                      _promptController.clear();
                      await provider.startAiPrompt(prompt);
                    },
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('发送'),
                    style: AppButtonStyles.primary(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final message = provider.isSharedSelection
        ? '当前会话将直接面向共享服务器执行命令，并把提问、步骤和执行结果写入本地与源端审计。'
        : '你可以点击左侧加号创建会话，也可以直接在下方输入需求开始第一轮对话。';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.auto_awesome, size: 40, color: AppColors.primary),
          const SizedBox(height: 12),
          const Text(
            '开始一个新的 AI 会话',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySessionTip(AppProvider provider) {
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
          const Text(
            '还没有会话',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '点击右上角的 + 新建会话，或者直接在下方输入框输入需求。',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: provider.selectedServer == null
                  ? null
                  : () => provider.createAiSession(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建会话'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySessionCard(
    BuildContext context,
    AppProvider provider,
    AiSessionRecord session, {
    required bool selected,
  }) {
    Future<void> confirmRename() async {
      final controller = TextEditingController(text: session.title);
      final renamed = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('重命名会话'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入新的会话名称',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (renamed != null && renamed.trim().isNotEmpty && mounted) {
        await provider.renameAiSession(session.id, renamed);
      }
    }

    Future<void> confirmDelete() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('删除会话'),
          content: const Text('删除后将同时移除该会话下的所有历史消息和 SSH 步骤记录，且无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                '删除',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await provider.deleteAiSession(session.id);
      }
    }

    return GestureDetector(
      onSecondaryTapDown: (details) async {
        final value = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: const [
                PopupMenuItem<String>(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('重命名会话'),
                    ],
                  ),
                ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                  SizedBox(width: 8),
                  Text('删除会话'),
                ],
              ),
            ),
          ],
        );
            if (value == 'rename' && mounted) {
              await confirmRename();
            }
        if (value == 'delete' && mounted) {
          await confirmDelete();
        }
      },
      onTap: () => provider.selectAiSession(session.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFeff6ff) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                    IconButton(
                      tooltip: '重命名会话',
                      onPressed: confirmRename,
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      splashRadius: 18,
                      visualDensity: VisualDensity.compact,
                    ),
                IconButton(
                  tooltip: '删除会话',
                  onPressed: confirmDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  splashRadius: 18,
                  visualDensity: VisualDensity.compact,
                ),
                _StatusBadge(status: session.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${session.updatedAt.month.toString().padLeft(2, '0')}-${session.updatedAt.day.toString().padLeft(2, '0')} '
              '${session.updatedAt.hour.toString().padLeft(2, '0')}:${session.updatedAt.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _StatusBadge extends StatelessWidget {
  final AiTaskStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AiTaskStatus.analyzing => ('分析中', AppColors.primary),
      AiTaskStatus.waitingConfirm => ('待确认', AppColors.warning),
      AiTaskStatus.running => ('进行中', AppColors.primary),
      AiTaskStatus.success => ('完成', AppColors.success),
      AiTaskStatus.failed => ('失败', AppColors.danger),
      AiTaskStatus.interrupted => ('已中断', AppColors.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StepStatusBadge extends StatelessWidget {
  final AiStepRecord step;

  const _StepStatusBadge({required this.step});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (step.status) {
      AiStepStatus.pending => ('待执行', AppColors.textMuted),
      AiStepStatus.waitingConfirm => ('待确认', AppColors.warning),
      AiStepStatus.running => ('执行中', AppColors.primary),
      AiStepStatus.success => ('成功', AppColors.success),
      AiStepStatus.failed => ('失败', AppColors.danger),
      AiStepStatus.skipped => ('已跳过', AppColors.textMuted),
      AiStepStatus.interrupted => ('已中断', AppColors.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
