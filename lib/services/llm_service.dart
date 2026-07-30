import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/server.dart';

class LlmPlannedStep {
  final String title;
  final String command;
  final String summary;
  final AiRiskLevel riskLevel;

  const LlmPlannedStep({
    required this.title,
    required this.command,
    required this.summary,
    required this.riskLevel,
  });
}

class LlmPlanResponse {
  final String analysis;
  final List<LlmPlannedStep> steps;

  const LlmPlanResponse({
    required this.analysis,
    required this.steps,
  });
}

class LlmExecutionReviewResponse {
  final String analysis;
  final bool isSatisfied;
  final String finalAnswer;
  final List<LlmPlannedStep> nextSteps;

  const LlmExecutionReviewResponse({
    required this.analysis,
    required this.isSatisfied,
    required this.finalAnswer,
    required this.nextSteps,
  });
}

class LlmTestConnectionResult {
  final bool success;
  final String message;
  final int? latencyMs;
  final List<String> models;

  const LlmTestConnectionResult({
    required this.success,
    required this.message,
    this.latencyMs,
    this.models = const <String>[],
  });
}

class LlmService {
  static const int _planMaxTokensCap = 1400;
  static const int _reviewMaxTokensCap = 1600;
  static const int _summaryMaxTokensCap = 900;

  static const String _systemPrompt =
      '你是 ShellGuard 的 Linux 运维 AI 助理。'
      '你的职责是把用户目标拆解为可以通过 SSH 执行的步骤。'
      '你不是直接执行命令的终端，而是在为 SSH 技能生成执行计划。'
      '每个步骤都必须是单条 shell 命令，能在 Linux 服务器上直接执行。'
      '优先先做检查，再做可能有副作用的操作。'
      '如果用户只是查询信息，尽量只输出只读命令，例如 docker ps、docker inspect、df、free、ps、systemctl status、journalctl、cat、grep。'
      '除非用户明确要求修改系统，否则不要生成 rm、reboot、shutdown、systemctl restart、iptables、ufw reset 等命令。'
      '如果需要获取某个问题的答案，先生成检查命令，再根据检查结果决定后续步骤。'
      '请只返回 JSON，不要返回 Markdown，不要使用代码块。'
      'JSON 结构必须为 {"analysis":"...","steps":[{"title":"...","command":"...","summary":"...","risk":"safe|low|medium|high"}]}。'
      'analysis 必须说明你为什么这样安排 SSH 检查步骤。'
      'steps 中禁止返回空命令，禁止返回多条命令混写成一个步骤。';

  final http.Client _client;

  LlmService({http.Client? client}) : _client = client ?? http.Client();

  Future<LlmPlanResponse> createPlan({
    required LlmProviderConfig provider,
    required String userPrompt,
    required Server server,
  }) async {
    final response = await _postChatCompletion(
      provider: provider,
      body: {
        'model': provider.model,
        'temperature': 0.2,
        'max_tokens': provider.maxTokens.clamp(256, _planMaxTokensCap),
        'response_format': {
          'type': 'json_object',
        },
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {
            'role': 'user',
            'content':
                '服务器信息: ${server.name} (${server.ip}), 用户=${server.username}。\n'
                '用户需求: $userPrompt\n'
                '请你为 SSH 技能输出执行计划。\n'
                '要求：\n'
                '1. 先检查、后操作；\n'
                '2. 每个 step 只能有一条 Linux shell 命令；\n'
                '3. 若是查询类需求，优先输出只读命令；\n'
                '4. risk 需按命令风险给出 safe/low/medium/high；\n'
                '5. 如果只靠一条检查命令就能回答问题，就不要编造多余操作。',
          },
        ],
      },
      timeout: _resolveTimeout(provider, isPlanning: true),
    );

    final content = _extractMessageContent(response);
    final decoded = json.decode(content) as Map<String, dynamic>;
    return LlmPlanResponse(
      analysis: (decoded['analysis'] as String? ?? '').trim(),
      steps: _parseSteps(decoded['steps'] as List<dynamic>?),
    );
  }

  Future<LlmExecutionReviewResponse> reviewExecution({
    required LlmProviderConfig provider,
    required String userPrompt,
    required Server server,
    required String previousAnalysis,
    String sessionSummary = '',
    List<Map<String, String>> historyMessages = const <Map<String, String>>[],
    required List<Map<String, String>> executedSteps,
  }) async {
    final conversationHistory = historyMessages.map((item) {
      return '${item['role']}: ${item['content']}';
    }).join('\n');
    final stepHistory = executedSteps.map((item) {
      return '步骤: ${item['title']}\n'
          '状态: ${item['status']}\n'
          '命令: ${item['command']}\n'
          '步骤说明:\n${item['summary']}\n'
          'stdout:\n${item['output']}\n'
          'stderr:\n${item['errorOutput']}\n';
    }).join('\n---\n');

    final response = await _postChatCompletion(
      provider: provider,
      body: {
        'model': provider.model,
        'temperature': 0.2,
        'max_tokens': provider.maxTokens.clamp(256, _reviewMaxTokensCap),
        'response_format': {
          'type': 'json_object',
        },
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {
            'role': 'user',
            'content':
                '服务器信息: ${server.name} (${server.ip}), 用户=${server.username}。\n'
                '会话摘要: ${sessionSummary.isEmpty ? '无' : sessionSummary}\n'
                '此前会话历史:\n${conversationHistory.isEmpty ? '无' : conversationHistory}\n'
                '原始用户需求: $userPrompt\n'
                '上一次分析: $previousAnalysis\n'
                '本轮已经执行过的 SSH 步骤如下:\n${stepHistory.isEmpty ? '无' : stepHistory}\n'
                '请根据这些执行结果判断需求是否已经满足。\n'
                '如果已经满足，请返回 JSON：'
                '{"analysis":"...","isSatisfied":true,"finalAnswer":"给用户的最终回答","steps":[]}\n'
                '如果还未满足，请返回 JSON：'
                '{"analysis":"...","isSatisfied":false,"finalAnswer":"","steps":[{"title":"...","command":"...","summary":"...","risk":"safe|low|medium|high"}]}\n'
                '要求：'
                '1. finalAnswer 必须直接回答用户问题；'
                '2. 如果继续执行，steps 只给下一阶段真正需要的新步骤；'
                '3. 不要重复已经执行过且已经拿到结果的命令；'
                '4. 如果从当前结果就能得出答案，不要再生成新步骤；'
                '5. 如果某一步状态是 skipped，说明该命令被用户拒绝执行，你必须基于“该步骤未执行”继续判断，不要假设它已经执行成功。',
          },
        ],
      },
      timeout: _resolveTimeout(provider, isPlanning: true),
    );

    final content = _extractMessageContent(response);
    final decoded = json.decode(content) as Map<String, dynamic>;
    return LlmExecutionReviewResponse(
      analysis: (decoded['analysis'] as String? ?? '').trim(),
      isSatisfied: (decoded['isSatisfied'] as bool?) ?? false,
      finalAnswer: (decoded['finalAnswer'] as String? ?? '').trim(),
      nextSteps: _parseSteps(decoded['steps'] as List<dynamic>?),
    );
  }

  Future<String> compressConversationHistory({
    required LlmProviderConfig provider,
    required Server server,
    required List<Map<String, String>> historyMessages,
  }) async {
    final content = historyMessages.map((item) {
      return '${item['role']}: ${item['content']}';
    }).join('\n');
    final response = await _postChatCompletion(
      provider: provider,
      body: {
        'model': provider.model,
        'temperature': 0.2,
        'max_tokens': _summaryMaxTokensCap,
        'messages': [
          {'role': 'system', 'content': '你是会话摘要助手，请将对话与 SSH 执行结果压缩成后续继续执行任务所需的关键信息。'},
          {
            'role': 'user',
            'content':
                '服务器信息: ${server.name} (${server.ip}), 用户=${server.username}\n'
                '请压缩下面的历史会话，保留：已确认的事实、已经执行过的命令及其关键结果、用户偏好、尚未完成的目标、风险点。\n'
                '不要保留冗余措辞，输出纯文本摘要。\n'
                '历史会话如下:\n$content',
          },
        ],
      },
      timeout: _resolveTimeout(provider, isPlanning: true),
    );
    return _extractMessageContent(response).trim();
  }

  Future<LlmTestConnectionResult> testConnection(
    LlmProviderConfig provider,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _postChatCompletion(
        provider: provider,
        body: {
          'model': provider.model,
          'max_tokens': 32,
          'messages': const [
            {'role': 'system', 'content': 'reply with ok'},
            {'role': 'user', 'content': 'ping'},
          ],
        },
        timeout: _resolveTimeout(provider, isPlanning: false),
      );
      stopwatch.stop();
      final _ = _extractMessageContent(response);
      return LlmTestConnectionResult(
        success: true,
        message: '连接测试成功',
        latencyMs: stopwatch.elapsedMilliseconds,
        models: <String>[provider.model],
      );
    } catch (e) {
      stopwatch.stop();
      return LlmTestConnectionResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _postChatCompletion({
    required LlmProviderConfig provider,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    final normalizedBaseUrl = provider.baseUrl.toLowerCase();
    final isArk = normalizedBaseUrl.contains('volces.com') || normalizedBaseUrl.contains('ark');
    try {
      return await _sendChatCompletion(
        provider: provider,
        body: body,
        timeout: timeout,
      );
    } on TimeoutException {
      if (!isArk) {
        rethrow;
      }
      return _sendChatCompletion(
        provider: provider,
        body: body,
        timeout: timeout + const Duration(seconds: 45),
      );
    }
  }

  Future<Map<String, dynamic>> _sendChatCompletion({
    required LlmProviderConfig provider,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    final uri = Uri.parse(_normalizeBaseUrl(provider.baseUrl));
    final response = await _client
        .post(
          uri,
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.authorizationHeader: 'Bearer ${provider.apiKey}',
          },
          body: json.encode(body),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'LLM 请求失败(${response.statusCode}): ${response.body}',
      );
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  String _extractMessageContent(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>? ?? const <dynamic>[];
    if (choices.isEmpty) {
      throw Exception('LLM 未返回可用结果');
    }
    final message = choices.first['message'] as Map<String, dynamic>? ?? const {};
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content;
    }
    throw Exception('LLM 返回内容为空');
  }

  String _normalizeBaseUrl(String baseUrl) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.endsWith('/api/v3')) {
      return '$normalized/chat/completions';
    }
    if (normalized.endsWith('/api/v3/chat/completions')) {
      return normalized;
    }
    if (normalized.endsWith('/chat/completions')) {
      return normalized;
    }
    if (normalized.endsWith('/v1')) {
      return '$normalized/chat/completions';
    }
    return '$normalized/v1/chat/completions';
  }

  Duration _resolveTimeout(
    LlmProviderConfig provider, {
    required bool isPlanning,
  }) {
    final normalized = provider.baseUrl.toLowerCase();
    final isArk = normalized.contains('volces.com') || normalized.contains('ark');
    if (isPlanning) {
      return isArk ? const Duration(seconds: 90) : const Duration(seconds: 60);
    }
    return isArk ? const Duration(seconds: 45) : const Duration(seconds: 20);
  }

  AiRiskLevel _parseRisk(String value) {
    switch (value) {
      case 'low':
        return AiRiskLevel.low;
      case 'medium':
        return AiRiskLevel.medium;
      case 'high':
        return AiRiskLevel.high;
      case 'safe':
      default:
        return AiRiskLevel.safe;
    }
  }

  List<LlmPlannedStep> _parseSteps(List<dynamic>? rawSteps) {
    return (rawSteps ?? const <dynamic>[])
        .map((dynamic step) {
          final map = step as Map<String, dynamic>;
          return LlmPlannedStep(
            title: (map['title'] as String? ?? '未命名步骤').trim(),
            command: (map['command'] as String? ?? '').trim(),
            summary: (map['summary'] as String? ?? '').trim(),
            riskLevel: _parseRisk((map['risk'] as String? ?? 'safe').trim()),
          );
        })
        .where((step) => step.command.isNotEmpty)
        .toList();
  }
}
