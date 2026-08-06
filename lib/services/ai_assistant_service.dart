import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ssh_manager.dart';
import '../models/server.dart';
import 'llm_service.dart';
import 'storage_service.dart';

typedef AiAuditLogger = Future<void> Function({
  required String action,
  required String summary,
  String detail,
  bool success,
});

class AiSessionRuntimeSnapshot {
  final AiSessionRecord session;
  final List<AiMessageRecord> messages;
  final Map<String, List<AiStepRecord>> stepsByMessageId;
  final String activeExecutionId;

  const AiSessionRuntimeSnapshot({
    required this.session,
    required this.messages,
    required this.stepsByMessageId,
    this.activeExecutionId = '',
  });
}

class AiCommandChunk {
  final String executionId;
  final String text;
  final bool isError;
  final bool isDone;

  const AiCommandChunk({
    required this.executionId,
    required this.text,
    this.isError = false,
    this.isDone = false,
  });
}

class AiCommandResult {
  final String stdout;
  final String stderr;
  final int? exitCode;
  final bool interrupted;

  const AiCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.interrupted,
  });
}

class AiCommandExecutionHandle {
  final String executionId;
  final Stream<AiCommandChunk> stream;
  final Future<AiCommandResult> result;

  const AiCommandExecutionHandle({
    required this.executionId,
    required this.stream,
    required this.result,
  });
}

abstract class AiCommandExecutor {
  Future<AiCommandExecutionHandle> executeUserCommandStream(String command);
  Future<AiCommandExecutionHandle> executePrivilegedUserCommandStream(String command);
  void interruptExecution(String executionId);
}

class LocalAiCommandExecutor implements AiCommandExecutor {
  final SshManager manager;

  const LocalAiCommandExecutor(this.manager);

  @override
  Future<AiCommandExecutionHandle> executeUserCommandStream(String command) async {
    final handle = await manager.executeUserCommandStream(command);
    return _wrap(handle);
  }

  @override
  Future<AiCommandExecutionHandle> executePrivilegedUserCommandStream(String command) async {
    final handle = await manager.executePrivilegedUserCommandStream(command);
    return _wrap(handle);
  }

  @override
  void interruptExecution(String executionId) {
    manager.interruptExecution(executionId);
  }

  AiCommandExecutionHandle _wrap(SshExecutionHandle handle) {
    return AiCommandExecutionHandle(
      executionId: handle.executionId,
      stream: handle.stream.map((chunk) {
        return AiCommandChunk(
          executionId: chunk.executionId,
          text: chunk.text,
          isError: chunk.isError,
          isDone: chunk.isDone,
        );
      }),
      result: handle.result.then((result) {
        return AiCommandResult(
          stdout: result.stdout,
          stderr: result.stderr,
          exitCode: result.exitCode,
          interrupted: result.interrupted,
        );
      }),
    );
  }
}

class SharedAiCommandExecutor implements AiCommandExecutor {
  final Future<String> Function({
    required String command,
    required bool privileged,
  }) runCommand;

  const SharedAiCommandExecutor({
    required this.runCommand,
  });

  @override
  Future<AiCommandExecutionHandle> executeUserCommandStream(String command) {
    return _run(command, privileged: false);
  }

  @override
  Future<AiCommandExecutionHandle> executePrivilegedUserCommandStream(String command) {
    return _run(command, privileged: true);
  }

  @override
  void interruptExecution(String executionId) {}

  Future<AiCommandExecutionHandle> _run(
    String command, {
    required bool privileged,
  }) async {
    final executionId = DateTime.now().microsecondsSinceEpoch.toString();
    final controller = StreamController<AiCommandChunk>.broadcast();
    final completer = Completer<AiCommandResult>();

    unawaited(() async {
      try {
        final output = await runCommand(command: command, privileged: privileged);
        if (output.isNotEmpty) {
          controller.add(
            AiCommandChunk(
              executionId: executionId,
              text: output,
            ),
          );
        }
        controller.add(
          AiCommandChunk(
            executionId: executionId,
            text: '',
            isDone: true,
          ),
        );
        await controller.close();
        completer.complete(
          AiCommandResult(
            stdout: output,
            stderr: '',
            exitCode: 0,
            interrupted: false,
          ),
        );
      } catch (error) {
        final message = error.toString();
        controller.add(
          AiCommandChunk(
            executionId: executionId,
            text: message,
            isError: true,
          ),
        );
        controller.add(
          AiCommandChunk(
            executionId: executionId,
            text: '',
            isDone: true,
          ),
        );
        await controller.close();
        completer.complete(
          AiCommandResult(
            stdout: '',
            stderr: message,
            exitCode: 1,
            interrupted: false,
          ),
        );
      }
    }());

    return AiCommandExecutionHandle(
      executionId: executionId,
      stream: controller.stream,
      result: completer.future,
    );
  }
}

class AiAssistantService {
  static const int _historyCompressionThreshold = 10;
  static const int _streamMaxChars = 8000;
  static const Duration _continuousCommandMaxDuration = Duration(seconds: 12);

  final StorageService _storageService;
  final LlmService _llmService;

  final Map<String, Completer<bool>> _confirmWaiters = {};
  final Map<String, AiSessionRuntimeSnapshot> _runtimeSessions = {};
  final Map<String, AiCommandExecutor> _sessionExecutors = {};
  final Map<String, Server> _sessionServers = {};
  final Map<String, LlmProviderConfig> _sessionProviders = {};
  final Map<String, AiAuditLogger> _sessionAuditLoggers = {};

  AiAssistantService(this._storageService, this._llmService);

  bool hasRuntimeSession(String sessionId) => _runtimeSessions.containsKey(sessionId);

  void removeRuntimeSession(String sessionId) {
    _runtimeSessions.remove(sessionId);
    _sessionExecutors.remove(sessionId);
    _sessionServers.remove(sessionId);
    _sessionProviders.remove(sessionId);
    _sessionAuditLoggers.remove(sessionId);
    _confirmWaiters.removeWhere((key, _) => key.startsWith('$sessionId:'));
  }

  Future<void> attachSessionRuntime({
    required AiSessionRecord session,
    required List<AiMessageRecord> messages,
    required Map<String, List<AiStepRecord>> stepsByMessageId,
    required Server server,
    required LlmProviderConfig provider,
    required AiCommandExecutor executor,
    AiAuditLogger? auditLogger,
    required VoidCallback onChanged,
  }) async {
    _runtimeSessions[session.id] = AiSessionRuntimeSnapshot(
      session: session,
      messages: messages,
      stepsByMessageId: stepsByMessageId,
    );
    _sessionExecutors[session.id] = executor;
    _sessionServers[session.id] = server;
    _sessionProviders[session.id] = provider;
    if (auditLogger != null) {
      _sessionAuditLoggers[session.id] = auditLogger;
    }
    onChanged();
  }

  List<AiSessionRuntimeSnapshot> get runtimeSessions {
    final items = _runtimeSessions.values.toList()
      ..sort((a, b) => b.session.updatedAt.compareTo(a.session.updatedAt));
    return items;
  }

  Future<AiSessionRuntimeSnapshot> createSession({
    required Server server,
    required LlmProviderConfig provider,
    required AiCommandExecutor executor,
    String? initialPrompt,
    AiAuditLogger? auditLogger,
    required VoidCallback onChanged,
  }) async {
    final sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    final now = DateTime.now();
    var session = AiSessionRecord(
      id: sessionId,
      serverId: server.id,
      serverName: server.name,
      title: (initialPrompt == null || initialPrompt.trim().isEmpty)
          ? '新会话'
          : initialPrompt.trim(),
      status: AiTaskStatus.success,
      createdAt: now,
      updatedAt: now,
    );

    await _storageService.saveAiSession(session);
    _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
      session: session,
      messages: const [],
      stepsByMessageId: const {},
    );
    _sessionExecutors[sessionId] = executor;
    _sessionServers[sessionId] = server;
    _sessionProviders[sessionId] = provider;
    if (auditLogger != null) {
      _sessionAuditLoggers[sessionId] = auditLogger;
      await _logAiAudit(
        sessionId,
        action: 'create_session',
        summary: session.title,
        detail: 'server=${server.name}',
      );
    }
    onChanged();

    if (initialPrompt != null && initialPrompt.trim().isNotEmpty) {
      return appendUserPrompt(
        sessionId: sessionId,
        prompt: initialPrompt,
        onChanged: onChanged,
      );
    }

    return _runtimeSessions[sessionId]!;
  }

  Future<AiSessionRuntimeSnapshot> appendUserPrompt({
    required String sessionId,
    required String prompt,
    required VoidCallback onChanged,
  }) async {
    final snapshot = _runtimeSessions[sessionId];
    final server = _sessionServers[sessionId];
    final provider = _sessionProviders[sessionId];
    final executor = _sessionExecutors[sessionId];
    if (snapshot == null || server == null || provider == null || executor == null) {
      throw Exception('会话不存在或运行环境未初始化');
    }

    final userMessageId = '${sessionId}_${DateTime.now().microsecondsSinceEpoch}_user';
    final assistantMessageId = '${sessionId}_${DateTime.now().microsecondsSinceEpoch}_assistant';
    final now = DateTime.now();

    final userMessage = AiMessageRecord(
      id: userMessageId,
      sessionId: sessionId,
      role: AiMessageRole.user,
      content: prompt.trim(),
      status: AiTaskStatus.success,
      createdAt: now,
      updatedAt: now,
    );
    var assistantMessage = AiMessageRecord(
      id: assistantMessageId,
      sessionId: sessionId,
      role: AiMessageRole.assistant,
      content: '',
      status: AiTaskStatus.analyzing,
      createdAt: now,
      updatedAt: now,
    );

    await _storageService.saveAiMessage(userMessage);
    await _storageService.saveAiMessage(assistantMessage);

    var updatedSession = snapshot.session.copyWith(
      title: snapshot.messages.isEmpty ? prompt.trim() : snapshot.session.title,
      status: AiTaskStatus.analyzing,
      updatedAt: now,
      errorMessage: null,
    );
    await _storageService.saveAiSession(updatedSession);

    _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
      session: updatedSession,
      messages: [
        ...snapshot.messages,
        userMessage,
        assistantMessage,
      ],
      stepsByMessageId: Map<String, List<AiStepRecord>>.from(snapshot.stepsByMessageId),
    );
    await _logAiAudit(
      sessionId,
      action: 'user_prompt',
      summary: prompt.trim(),
      detail: 'server=${server.name}',
    );
    onChanged();

    try {
      await _compressSessionHistoryIfNeeded(
        sessionId: sessionId,
        onChanged: onChanged,
      );

      final plan = await _llmService.createPlan(
        provider: provider,
        userPrompt: prompt.trim(),
        server: server,
      );
      if (plan.steps.isEmpty) {
        throw Exception('LLM 未生成可执行的 SSH 步骤，请检查模型配置或提示词。');
      }

      final steps = _buildRecords(
        messageId: assistantMessageId,
        plannedSteps: plan.steps,
      );

      assistantMessage = assistantMessage.copyWith(
        analysis: plan.analysis,
        status: AiTaskStatus.running,
        updatedAt: DateTime.now(),
      );
      updatedSession = updatedSession.copyWith(
        status: assistantMessage.status,
        updatedAt: DateTime.now(),
      );

      await _storageService.saveAiMessage(assistantMessage);
      await _storageService.saveAiMessageSteps(assistantMessageId, steps);
      await _storageService.saveAiSession(updatedSession);

      final nextMessages = _replaceMessage(
        _runtimeSessions[sessionId]!.messages,
        assistantMessage,
      );
      final nextStepsByMessage = Map<String, List<AiStepRecord>>.from(
        _runtimeSessions[sessionId]!.stepsByMessageId,
      )..[assistantMessageId] = steps;

      _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
        session: updatedSession,
        messages: nextMessages,
        stepsByMessageId: nextStepsByMessage,
      );
      onChanged();

      unawaited(
        _runMessageSteps(
          sessionId: sessionId,
          assistantMessageId: assistantMessageId,
          prompt: prompt.trim(),
          executor: executor,
          onChanged: onChanged,
        ),
      );
      return _runtimeSessions[sessionId]!;
    } catch (e) {
      assistantMessage = assistantMessage.copyWith(
        status: AiTaskStatus.failed,
        analysis: '任务规划失败',
        errorMessage: _normalizeTaskError(e),
        updatedAt: DateTime.now(),
      );
      updatedSession = updatedSession.copyWith(
        status: AiTaskStatus.failed,
        errorMessage: assistantMessage.errorMessage,
        updatedAt: DateTime.now(),
      );
      await _storageService.saveAiMessage(assistantMessage);
      await _storageService.saveAiSession(updatedSession);
      await _logAiAudit(
        sessionId,
        action: 'plan_failed',
        summary: prompt.trim(),
        detail: assistantMessage.errorMessage ?? '任务规划失败',
        success: false,
      );
      _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
        session: updatedSession,
        messages: _replaceMessage(_runtimeSessions[sessionId]!.messages, assistantMessage),
        stepsByMessageId: _runtimeSessions[sessionId]!.stepsByMessageId,
      );
      onChanged();
      return _runtimeSessions[sessionId]!;
    }
  }

  Future<void> approveStep(
    String sessionId,
    String messageId,
    String stepId, {
    bool execute = true,
  }) async {
    final waiter = _confirmWaiters['$sessionId:$messageId:$stepId'];
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(execute);
    }
  }

  Future<void> interruptSession(
    String sessionId, {
    required VoidCallback onChanged,
  }) async {
    final snapshot = _runtimeSessions[sessionId];
    if (snapshot == null) {
      return;
    }
    final executor = _sessionExecutors[sessionId];
    if (executor != null && snapshot.activeExecutionId.isNotEmpty) {
      executor.interruptExecution(snapshot.activeExecutionId);
    }

    final updatedSession = snapshot.session.copyWith(
      status: AiTaskStatus.interrupted,
      updatedAt: DateTime.now(),
    );
    await _storageService.saveAiSession(updatedSession);

    final updatedMessages = snapshot.messages.map((message) {
      if (message.status == AiTaskStatus.running ||
          message.status == AiTaskStatus.waitingConfirm ||
          message.status == AiTaskStatus.analyzing) {
        return message.copyWith(
          status: AiTaskStatus.interrupted,
          updatedAt: DateTime.now(),
        );
      }
      return message;
    }).toList();
    for (final message in updatedMessages) {
      await _storageService.saveAiMessage(message);
    }

    _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
      session: updatedSession,
      messages: updatedMessages,
      stepsByMessageId: snapshot.stepsByMessageId,
    );
    onChanged();
  }

  Future<void> _runMessageSteps({
    required String sessionId,
    required String assistantMessageId,
    required String prompt,
    required AiCommandExecutor executor,
    required VoidCallback onChanged,
  }) async {
    final provider = _sessionProviders[sessionId];
    final server = _sessionServers[sessionId];
    if (provider == null || server == null) {
      return;
    }

    while (true) {
      final snapshot = _runtimeSessions[sessionId];
      if (snapshot == null) {
        return;
      }
      if (snapshot.session.status == AiTaskStatus.interrupted) {
        return;
      }
      final steps = snapshot.stepsByMessageId[assistantMessageId] ?? const <AiStepRecord>[];
      final pendingIndex = steps.indexWhere((step) {
        return step.status == AiStepStatus.pending ||
            step.status == AiStepStatus.waitingConfirm;
      });
      if (pendingIndex == -1) {
        break;
      }

      var step = steps[pendingIndex];
      if (step.requiresConfirmation) {
        if (step.status != AiStepStatus.waitingConfirm) {
          step = step.copyWith(status: AiStepStatus.waitingConfirm);
          await _replaceStep(
            sessionId: sessionId,
            messageId: assistantMessageId,
            updatedStep: step,
            onChanged: onChanged,
          );
          await _updateMessageStatus(
            sessionId: sessionId,
            messageId: assistantMessageId,
            status: AiTaskStatus.waitingConfirm,
            onChanged: onChanged,
          );
        }
        final allowed = await _waitForConfirmation(
          sessionId,
          assistantMessageId,
          step.id,
        );
        if (!allowed) {
          step = step.copyWith(
            status: AiStepStatus.skipped,
            summary: step.summary.isEmpty
                ? '用户拒绝执行该风险命令，系统已跳过此步骤。'
                : '${step.summary}\n用户拒绝执行该风险命令，系统已跳过此步骤。',
            finishedAt: DateTime.now(),
          );
          await _replaceStep(
            sessionId: sessionId,
            messageId: assistantMessageId,
            updatedStep: step,
            onChanged: onChanged,
          );
          await _updateMessageStatus(
            sessionId: sessionId,
            messageId: assistantMessageId,
            status: AiTaskStatus.running,
            onChanged: onChanged,
          );
          await _logAiAudit(
            sessionId,
            action: 'step_skipped',
            summary: step.command,
            detail: '用户拒绝执行高风险步骤: ${step.title}',
          );
          continue;
        }
        step = step.copyWith(status: AiStepStatus.pending);
        await _replaceStep(
          sessionId: sessionId,
          messageId: assistantMessageId,
          updatedStep: step,
          onChanged: onChanged,
        );
        await _updateMessageStatus(
          sessionId: sessionId,
          messageId: assistantMessageId,
          status: AiTaskStatus.running,
          onChanged: onChanged,
        );
      }

      final running = step.copyWith(
        status: AiStepStatus.running,
        startedAt: DateTime.now(),
        output: '',
        errorOutput: '',
      );
      await _replaceStep(
        sessionId: sessionId,
        messageId: assistantMessageId,
        updatedStep: running,
        onChanged: onChanged,
      );

      final result = await _executeStepWithAutoPrivilege(
        executor: executor,
        sessionId: sessionId,
        messageId: assistantMessageId,
        stepId: running.id,
        command: running.command,
        onChanged: onChanged,
      );

      final current = _findStep(sessionId, assistantMessageId, running.id);
      if (current == null) {
        continue;
      }
      final finalStep = current.copyWith(
        status: result.interrupted
            ? AiStepStatus.interrupted
            : (result.exitCode == null || result.exitCode == 0)
                ? AiStepStatus.success
                : AiStepStatus.failed,
        finishedAt: DateTime.now(),
      );
      await _replaceStep(
        sessionId: sessionId,
        messageId: assistantMessageId,
        updatedStep: finalStep,
        onChanged: onChanged,
      );
      await _logAiAudit(
        sessionId,
        action: 'execute_step',
        summary: running.command,
        detail: _buildStepAuditDetail(finalStep),
        success: finalStep.status == AiStepStatus.success,
      );
      if (result.interrupted) {
        return;
      }
    }

    await _reviewMessageExecution(
      sessionId: sessionId,
      messageId: assistantMessageId,
      prompt: prompt,
      onChanged: onChanged,
    );
  }

  Future<void> _reviewMessageExecution({
    required String sessionId,
    required String messageId,
    required String prompt,
    required VoidCallback onChanged,
  }) async {
    final snapshot = _runtimeSessions[sessionId];
    final provider = _sessionProviders[sessionId];
    final server = _sessionServers[sessionId];
    if (snapshot == null || provider == null || server == null) {
      return;
    }

    final message = _findMessage(sessionId, messageId);
    if (message == null) {
      return;
    }
    final steps = snapshot.stepsByMessageId[messageId] ?? const <AiStepRecord>[];
    final executedSteps = steps.map((item) {
      return {
        'title': item.title,
        'command': item.command,
        'status': item.status.name,
        'summary': item.summary,
        'output': item.output,
        'errorOutput': item.errorOutput,
      };
    }).toList();
    final historyMessages = snapshot.messages.map((item) {
      final content = item.role == AiMessageRole.assistant
          ? (item.finalAnswer.isNotEmpty ? item.finalAnswer : item.analysis)
          : item.content;
      return {
        'role': item.role.name,
        'content': content,
      };
    }).toList();

    final review = await _llmService.reviewExecution(
      provider: provider,
      userPrompt: prompt,
      server: server,
      previousAnalysis: message.analysis,
      sessionSummary: snapshot.session.compressedContext,
      historyMessages: historyMessages,
      executedSteps: executedSteps,
    );

    var updatedMessage = message.copyWith(
      analysis: review.analysis.isEmpty ? message.analysis : review.analysis,
      finalAnswer: review.finalAnswer,
      status: review.isSatisfied
          ? AiTaskStatus.success
          : steps.any((step) => step.status == AiStepStatus.failed)
              ? AiTaskStatus.failed
              : AiTaskStatus.running,
      updatedAt: DateTime.now(),
      errorMessage: steps.any((step) => step.status == AiStepStatus.failed)
          ? (steps.lastWhere((step) => step.status == AiStepStatus.failed).errorOutput)
          : null,
    );

    final nextSteps = review.nextSteps.isEmpty
        ? const <AiStepRecord>[]
        : _buildRecords(
            messageId: messageId,
            plannedSteps: review.nextSteps,
            startIndex: steps.length,
          );

    final mergedSteps = <AiStepRecord>[
      ...steps,
      ...nextSteps,
    ];

    final updatedSession = snapshot.session.copyWith(
      status: updatedMessage.status,
      title: snapshot.session.title == '新会话'
          ? prompt
          : snapshot.session.title,
      errorMessage: updatedMessage.errorMessage,
      updatedAt: DateTime.now(),
    );

    await _storageService.saveAiMessage(updatedMessage);
    if (nextSteps.isNotEmpty) {
      await _storageService.saveAiMessageSteps(messageId, nextSteps);
    }
    await _storageService.saveAiSession(updatedSession);

    _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
      session: updatedSession,
      messages: _replaceMessage(snapshot.messages, updatedMessage),
      stepsByMessageId: {
        ...snapshot.stepsByMessageId,
        messageId: mergedSteps,
      },
    );
    await _logAiAudit(
      sessionId,
      action: review.isSatisfied ? 'assistant_answer' : 'review_iteration',
      summary: prompt,
      detail: review.finalAnswer.isNotEmpty ? review.finalAnswer : updatedMessage.analysis,
      success: updatedMessage.status != AiTaskStatus.failed,
    );
    onChanged();

    if (nextSteps.isNotEmpty) {
      final nextExecutor = _sessionExecutors[sessionId];
      if (nextExecutor == null) {
        return;
      }
      await _runMessageSteps(
        sessionId: sessionId,
        assistantMessageId: messageId,
        prompt: prompt,
        executor: nextExecutor,
        onChanged: onChanged,
      );
    }
  }

  Future<void> _compressSessionHistoryIfNeeded({
    required String sessionId,
    required VoidCallback onChanged,
  }) async {
    final snapshot = _runtimeSessions[sessionId];
    final provider = _sessionProviders[sessionId];
    final server = _sessionServers[sessionId];
    if (snapshot == null || provider == null || server == null) {
      return;
    }
    if (snapshot.messages.length < _historyCompressionThreshold) {
      return;
    }
    final historyMessages = snapshot.messages.map((item) {
      final content = item.role == AiMessageRole.assistant
          ? (item.finalAnswer.isNotEmpty ? item.finalAnswer : item.analysis)
          : item.content;
      return {
        'role': item.role.name,
        'content': content,
      };
    }).toList();
    final summary = await _llmService.compressConversationHistory(
      provider: provider,
      server: server,
      historyMessages: historyMessages,
    );
    if (summary.isEmpty) {
      return;
    }
    final updatedSession = snapshot.session.copyWith(
      compressedContext: summary,
      updatedAt: DateTime.now(),
    );
    await _storageService.saveAiSession(updatedSession);
    _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
      session: updatedSession,
      messages: snapshot.messages,
      stepsByMessageId: snapshot.stepsByMessageId,
    );
    onChanged();
  }

  Future<bool> _waitForConfirmation(
    String sessionId,
    String messageId,
    String stepId,
  ) async {
    final key = '$sessionId:$messageId:$stepId';
    final completer = Completer<bool>();
    _confirmWaiters[key] = completer;
    try {
      return await completer.future;
    } finally {
      _confirmWaiters.remove(key);
    }
  }

  Future<AiCommandResult> _executeStepWithAutoPrivilege({
    required AiCommandExecutor executor,
    required String sessionId,
    required String messageId,
    required String stepId,
    required String command,
    required VoidCallback onChanged,
  }) async {
    final effectiveCommand = _wrapContinuousCommandIfNeeded(command);
    var result = await _runHandle(
      handle: await executor.executeUserCommandStream(effectiveCommand),
      sessionId: sessionId,
      messageId: messageId,
      stepId: stepId,
      onChanged: onChanged,
    );

    if (_shouldRetryWithPrivilege(command, result)) {
      final current = _findStep(sessionId, messageId, stepId);
      if (current != null) {
        final retried = current.copyWith(
          summary: current.summary.isEmpty
              ? _buildRetrySummary(command)
              : '${current.summary}\n${_buildRetrySummary(command)}',
          output: '',
          errorOutput: '',
        );
        await _replaceStep(
          sessionId: sessionId,
          messageId: messageId,
          updatedStep: retried,
          onChanged: onChanged,
        );
      }
      result = await _runHandle(
        handle: await executor.executePrivilegedUserCommandStream(effectiveCommand),
        sessionId: sessionId,
        messageId: messageId,
        stepId: stepId,
        onChanged: onChanged,
      );
    }

    return result;
  }

  Future<AiCommandResult> _runHandle({
    required AiCommandExecutionHandle handle,
    required String sessionId,
    required String messageId,
    required String stepId,
    required VoidCallback onChanged,
  }) async {
    final snapshot = _runtimeSessions[sessionId];
    if (snapshot != null) {
      _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
        session: snapshot.session,
        messages: snapshot.messages,
        stepsByMessageId: snapshot.stepsByMessageId,
        activeExecutionId: handle.executionId,
      );
      onChanged();
    }

    await for (final chunk in handle.stream) {
      if (chunk.isDone) {
        break;
      }
      final current = _findStep(sessionId, messageId, stepId);
      if (current == null) {
        continue;
      }
      final truncated = _appendWithLimit(
        existing: chunk.isError ? current.errorOutput : current.output,
        incoming: chunk.text,
      );
      final updated = chunk.isError
          ? current.copyWith(errorOutput: truncated)
          : current.copyWith(output: truncated);
      await _replaceStep(
        sessionId: sessionId,
        messageId: messageId,
        updatedStep: updated,
        onChanged: onChanged,
      );
    }

    return handle.result;
  }

  bool _shouldRetryWithPrivilege(String command, AiCommandResult result) {
    if (result.interrupted) {
      return false;
    }
    final normalizedCommand = command.trimLeft().toLowerCase();
    if (normalizedCommand.startsWith('sudo ')) {
      return false;
    }
    final stderr = '${result.stderr}\n${result.stdout}'.toLowerCase();
    return stderr.contains('permission denied') ||
        stderr.contains('operation not permitted') ||
        stderr.contains(
          'got permission denied while trying to connect to the docker daemon socket',
        );
  }

  List<AiStepRecord> _buildRecords({
    required String messageId,
    required List<LlmPlannedStep> plannedSteps,
    int startIndex = 0,
  }) {
    final steps = <AiStepRecord>[];
    for (var i = 0; i < plannedSteps.length; i++) {
      final planned = plannedSteps[i];
      final orderIndex = startIndex + i;
      final stepId = '${messageId}_$orderIndex';
      final riskLevel = _resolveRisk(planned.command, planned.riskLevel);
      steps.add(
        AiStepRecord(
          id: stepId,
          taskId: messageId,
          title: planned.title,
          command: planned.command,
          summary: _isContinuousCommand(planned.command.trim().toLowerCase())
              ? (planned.summary.isEmpty
                  ? '该命令会持续输出，系统将自动限制执行时长并截断返回结果。'
                  : '${planned.summary}\n该命令会持续输出，系统将自动限制执行时长并截断返回结果。')
              : planned.summary,
          status: AiStepStatus.pending,
          riskLevel: riskLevel,
          requiresConfirmation: riskLevel != AiRiskLevel.safe,
          orderIndex: orderIndex,
        ),
      );
    }
    return steps;
  }

  AiRiskLevel _resolveRisk(String command, AiRiskLevel suggested) {
    final normalized = command.toLowerCase();
    const highRiskPatterns = <String>[
      'rm -rf',
      'mkfs',
      'shutdown',
      'reboot',
      'poweroff',
      'dd if=',
      'ufw reset',
    ];
    const mediumRiskPatterns = <String>[
      'systemctl restart',
      'systemctl stop',
      'tee /etc/',
      'iptables',
      'ufw allow',
      'ufw deny',
      'docker rm',
      'tail -f',
      'journalctl -f',
      'watch ',
      'ping ',
    ];
    if (highRiskPatterns.any(normalized.contains)) {
      return AiRiskLevel.high;
    }
    if (mediumRiskPatterns.any(normalized.contains)) {
      return AiRiskLevel.medium;
    }
    return suggested;
  }

  String _normalizeTaskError(Object error) {
    final message = error.toString();
    if (message.contains('TimeoutException')) {
      return 'LLM 响应超时，请检查模型接口地址、模型标识或稍后重试。';
    }
    if (message.contains('InvalidEndpointOrModel.NotFound')) {
      return '模型或接入点不存在，请优先使用火山方舟控制台中的 Endpoint ID，或检查模型 ID 是否正确。';
    }
    return message;
  }

  Future<void> _replaceStep({
    required String sessionId,
    required String messageId,
    required AiStepRecord updatedStep,
    required VoidCallback onChanged,
  }) async {
    final snapshot = _runtimeSessions[sessionId];
    if (snapshot == null) {
      return;
    }
    final steps = [
      ...(snapshot.stepsByMessageId[messageId] ?? const <AiStepRecord>[]),
    ].map((step) {
      return step.id == updatedStep.id ? updatedStep : step;
    }).toList();
    await _storageService.saveAiMessageSteps(messageId, <AiStepRecord>[updatedStep]);
    _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
      session: snapshot.session.copyWith(updatedAt: DateTime.now()),
      messages: snapshot.messages,
      stepsByMessageId: {
        ...snapshot.stepsByMessageId,
        messageId: steps,
      },
      activeExecutionId: snapshot.activeExecutionId,
    );
    onChanged();
  }

  Future<void> _updateMessageStatus({
    required String sessionId,
    required String messageId,
    required AiTaskStatus status,
    required VoidCallback onChanged,
  }) async {
    final snapshot = _runtimeSessions[sessionId];
    if (snapshot == null) {
      return;
    }
    final message = _findMessage(sessionId, messageId);
    if (message == null) {
      return;
    }
    final updatedMessage = message.copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    final updatedSession = snapshot.session.copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    await _storageService.saveAiMessage(updatedMessage);
    await _storageService.saveAiSession(updatedSession);
    _runtimeSessions[sessionId] = AiSessionRuntimeSnapshot(
      session: updatedSession,
      messages: _replaceMessage(snapshot.messages, updatedMessage),
      stepsByMessageId: snapshot.stepsByMessageId,
      activeExecutionId: snapshot.activeExecutionId,
    );
    onChanged();
  }

  AiMessageRecord? _findMessage(String sessionId, String messageId) {
    final snapshot = _runtimeSessions[sessionId];
    if (snapshot == null) {
      return null;
    }
    for (final message in snapshot.messages) {
      if (message.id == messageId) {
        return message;
      }
    }
    return null;
  }

  AiStepRecord? _findStep(String sessionId, String messageId, String stepId) {
    final snapshot = _runtimeSessions[sessionId];
    if (snapshot == null) {
      return null;
    }
    for (final step in snapshot.stepsByMessageId[messageId] ?? const <AiStepRecord>[]) {
      if (step.id == stepId) {
        return step;
      }
    }
    return null;
  }

  List<AiMessageRecord> _replaceMessage(
    List<AiMessageRecord> messages,
    AiMessageRecord updatedMessage,
  ) {
    return messages.map((message) {
      return message.id == updatedMessage.id ? updatedMessage : message;
    }).toList();
  }

  String _appendWithLimit({
    required String existing,
    required String incoming,
  }) {
    final merged = '$existing$incoming';
    if (merged.length <= _streamMaxChars) {
      return merged;
    }
    return '${merged.substring(0, _streamMaxChars)}\n\n[输出已截断，超出 $_streamMaxChars 字符]';
  }

  Future<void> _logAiAudit(
    String sessionId, {
    required String action,
    required String summary,
    String detail = '',
    bool success = true,
  }) async {
    final logger = _sessionAuditLoggers[sessionId];
    if (logger == null) {
      return;
    }
    try {
      final server = _sessionServers[sessionId];
      final taggedDetail = <String>[
        '[[session_id:$sessionId]]',
        if (server != null) '[[server_name:${server.name}]]',
        if (detail.trim().isNotEmpty) detail.trim(),
      ].join('\n');
      await logger(
        action: action,
        summary: _truncateAuditText(summary, limit: 400),
        detail: _truncateAuditText(taggedDetail, limit: 4000),
        success: success,
      );
    } catch (_) {}
  }

  String _buildStepAuditDetail(AiStepRecord step) {
    final buffer = StringBuffer()
      ..writeln('title=${step.title}')
      ..writeln('status=${step.status.name}');
    if (step.summary.isNotEmpty) {
      buffer.writeln('summary=${step.summary}');
    }
    if (step.output.isNotEmpty) {
      buffer.writeln('stdout=${step.output}');
    }
    if (step.errorOutput.isNotEmpty) {
      buffer.writeln('stderr=${step.errorOutput}');
    }
    return buffer.toString().trim();
  }

  String _truncateAuditText(String value, {required int limit}) {
    if (value.length <= limit) {
      return value;
    }
    return '${value.substring(0, limit)}\n\n[已截断，原始内容超出 $limit 字符]';
  }

  String _wrapContinuousCommandIfNeeded(String command) {
    final normalized = command.trim().toLowerCase();
    if (_isContinuousCommand(normalized)) {
      final safeCommand = command.replaceAll("'", r"'\''");
      return "timeout ${_continuousCommandMaxDuration.inSeconds}s bash -lc '$safeCommand'";
    }
    return command;
  }

  bool _isContinuousCommand(String normalizedCommand) {
    return normalizedCommand.contains('tail -f') ||
        normalizedCommand.contains('journalctl -f') ||
        normalizedCommand.startsWith('watch ') ||
        normalizedCommand.startsWith('ping ') ||
        normalizedCommand.contains(' ping ');
  }

  String _buildRetrySummary(String command) {
    if (_isContinuousCommand(command.trim().toLowerCase())) {
      return '检测到权限不足，已自动使用 sudo 重试；该命令属于持续流命令，系统已自动限制执行时长并截断输出。';
    }
    return '检测到权限不足，已自动使用 sudo 重试。';
  }
}
