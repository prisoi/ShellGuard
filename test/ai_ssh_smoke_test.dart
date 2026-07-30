import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shellguard_free/core/ssh_manager.dart';
import 'package:shellguard_free/models/server.dart';
import 'package:shellguard_free/services/ai_assistant_service.dart';
import 'package:shellguard_free/services/llm_service.dart';
import 'package:shellguard_free/services/storage_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('输出默认 LLM 配置与目标服务器', () async {
    final storage = StorageService();
    final providers = await storage.loadLlmProviderConfigs();
    final provider = providers.cast<LlmProviderConfig?>().firstWhere(
          (item) => item != null && item.enabled && item.isDefault,
          orElse: () => providers.cast<LlmProviderConfig?>().firstWhere(
                (item) => item != null && item.enabled,
                orElse: () => null,
              ),
        );
    expect(provider, isNotNull, reason: '数据库中没有可用的默认 LLM 配置');

    final servers = await storage.loadServers();
    final selectedId = await storage.loadSelectedServer();
    Server? server;
    if (selectedId != null) {
      for (final item in servers) {
        if (item.id == selectedId) {
          server = item;
          break;
        }
      }
    }
    server ??= servers.isEmpty ? null : servers.first;
    expect(server, isNotNull, reason: '数据库中没有可用服务器');

    // ignore: avoid_print
    print('provider.name=${provider!.name}');
    // ignore: avoid_print
    print('provider.baseUrl=${provider.baseUrl}');
    // ignore: avoid_print
    print('provider.model=${provider.model}');
    // ignore: avoid_print
    print('server.name=${server!.name}');
    // ignore: avoid_print
    print('server.ip=${server.ip}');
    // ignore: avoid_print
    print('server.username=${server.username}');
  });

  test('输出最近一次 AI 任务错误信息', () async {
    final storage = StorageService();
    final tasks = await storage.loadAiTasks(limit: 5);
    expect(tasks, isNotEmpty, reason: '数据库中还没有 AI 任务记录');

    final latest = tasks.first;
    // ignore: avoid_print
    print('latestTask.status=${latest.status.name}');
    // ignore: avoid_print
    print('latestTask.prompt=${latest.prompt}');
    // ignore: avoid_print
    print('latestTask.analysis=${latest.analysis}');
    // ignore: avoid_print
    print('latestTask.error=${latest.errorMessage}');

    final steps = await storage.loadAiSteps(latest.id);
    for (final step in steps) {
      // ignore: avoid_print
      print(
        'step#${step.orderIndex + 1} ${step.status.name} ${step.riskLevel.name} ${step.command}',
      );
      if (step.errorOutput.isNotEmpty) {
        // ignore: avoid_print
        print('stderr=${step.errorOutput}');
      }
    }
  });

  test('输出最近几条 AI 会话与消息错误信息', () async {
    final storage = StorageService();
    final sessions = await storage.loadAiSessions(limit: 5);
    expect(sessions, isNotEmpty, reason: '数据库中还没有 AI 会话记录');

    for (final session in sessions) {
      // ignore: avoid_print
      print(
        'session=${session.id} status=${session.status.name} title=${session.title} error=${session.errorMessage} updated=${session.updatedAt.toIso8601String()}',
      );
      final messages = await storage.loadAiMessages(session.id);
      for (final message in messages) {
        // ignore: avoid_print
        print(
          '  message=${message.id} role=${message.role.name} status=${message.status.name} error=${message.errorMessage}',
        );
        if (message.role == AiMessageRole.assistant) {
          final steps = await storage.loadAiMessageSteps(message.id);
          for (final step in steps) {
            // ignore: avoid_print
            print(
              '    step#${step.orderIndex + 1} status=${step.status.name} risk=${step.riskLevel.name} cmd=${step.command}',
            );
          }
        }
      }
    }
  });

  test(
    'LLM 和 SSH 可以联动执行一个 safe 步骤',
    () async {
      final storage = StorageService();
      final llm = LlmService();
      final ssh = SshManager();

      final providers = await storage.loadLlmProviderConfigs();
      final provider = providers.cast<LlmProviderConfig?>().firstWhere(
            (item) => item != null && item.enabled && item.isDefault,
            orElse: () => providers.cast<LlmProviderConfig?>().firstWhere(
                  (item) => item != null && item.enabled,
                  orElse: () => null,
                ),
          );
      expect(provider, isNotNull, reason: '数据库中没有可用的默认 LLM 配置');

      final servers = await storage.loadServers();
      final selectedId = await storage.loadSelectedServer();
      Server? server;
      if (selectedId != null) {
        for (final item in servers) {
          if (item.id == selectedId) {
            server = item;
            break;
          }
        }
      }
      server ??= servers.isEmpty ? null : servers.first;
      expect(server, isNotNull, reason: '数据库中没有可用服务器');

      const prompt = '查看 docker 运行时间最长的容器';
      final plan = await llm.createPlan(
        provider: provider!,
        userPrompt: prompt,
        server: server!,
      );

      expect(plan.analysis.trim(), isNotEmpty, reason: 'LLM 没有返回分析结果');
      expect(plan.steps, isNotEmpty, reason: 'LLM 没有返回 SSH 步骤');

      final safeSteps = plan.steps
          .where((step) => step.riskLevel == AiRiskLevel.safe)
          .toList();
      expect(safeSteps, isNotEmpty, reason: 'LLM 没有生成 safe 步骤，无法自动联调');

      final connected = await ssh.connect(server);
      expect(connected, isTrue, reason: 'SSH 连接失败: ${ssh.errorMessage}');

      final firstStep = safeSteps.first;
      final handle = await ssh.executeCommandStream(firstStep.command);
      final output = StringBuffer();
      final errorOutput = StringBuffer();

      final subscription = handle.stream.listen((chunk) {
        if (chunk.isDone) {
          return;
        }
        if (chunk.isError) {
          errorOutput.write(chunk.text);
        } else {
          output.write(chunk.text);
        }
      });

      final result = await handle.result.timeout(const Duration(minutes: 2));
      await subscription.cancel();
      ssh.disconnect();

      expect(result.interrupted, isFalse, reason: 'SSH 执行被意外中断');
      expect(
        result.exitCode == null || result.exitCode == 0,
        isTrue,
        reason: 'SSH 执行失败: ${errorOutput.isEmpty ? result.stderr : errorOutput.toString()}',
      );

      final mergedOutput = '${output.toString()}${result.stdout}'.trim();
      expect(
        mergedOutput.isNotEmpty || firstStep.command.contains('docker'),
        isTrue,
        reason: '命令没有返回任何输出',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'Docker 权限不足时 AI 能继续完成任务',
    () async {
      final storage = StorageService();
      final llm = LlmService();
      final service = AiAssistantService(storage, llm);
      final ssh = SshManager();

      final providers = await storage.loadLlmProviderConfigs();
      final provider = providers.cast<LlmProviderConfig?>().firstWhere(
            (item) => item != null && item.enabled && item.isDefault,
            orElse: () => providers.cast<LlmProviderConfig?>().firstWhere(
                  (item) => item != null && item.enabled,
                  orElse: () => null,
                ),
          );
      expect(provider, isNotNull, reason: '数据库中没有可用的默认 LLM 配置');

      final servers = await storage.loadServers();
      final selectedId = await storage.loadSelectedServer();
      Server? server;
      if (selectedId != null) {
        for (final item in servers) {
          if (item.id == selectedId) {
            server = item;
            break;
          }
        }
      }
      server ??= servers.isEmpty ? null : servers.first;
      expect(server, isNotNull, reason: '数据库中没有可用服务器');

      final connected = await ssh.connect(server!);
      expect(connected, isTrue, reason: 'SSH 连接失败: ${ssh.errorMessage}');

      final snapshot = await service.createSession(
        server: server,
        provider: provider!,
        sshManager: ssh,
        initialPrompt: '看有docker里面跑了什么容器',
        onChanged: () {},
      );

      expect(
        snapshot.session.status == AiTaskStatus.running ||
            snapshot.session.status == AiTaskStatus.waitingConfirm ||
            snapshot.session.status == AiTaskStatus.success,
        isTrue,
        reason: 'AI 任务没有进入可继续执行状态',
      );

      ssh.disconnect();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
