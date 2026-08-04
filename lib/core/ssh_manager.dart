import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/server.dart';

typedef CommandCallback = void Function(String result, String? error);

class TransferCancelledException implements Exception {
  final String message;

  const TransferCancelledException([this.message = '传输已取消']);

  @override
  String toString() => message;
}

class TransferCancellationToken {
  bool _isCancelled = false;
  final List<Future<void> Function()> _callbacks = [];

  bool get isCancelled => _isCancelled;

  void bind(Future<void> Function() callback) {
    if (_isCancelled) {
      unawaited(callback());
      return;
    }
    _callbacks.add(callback);
  }

  Future<void> cancel() async {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final callbacks = List<Future<void> Function()>.from(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      try {
        await callback();
      } catch (_) {}
    }
  }
}

class FileListResult {
  final List<FileInfo> files;
  final String resolvedPath;

  const FileListResult({required this.files, required this.resolvedPath});
}

class DirectoryResolution {
  final String requestedPath;
  final String resolvedPath;
  final bool exists;

  const DirectoryResolution({
    required this.requestedPath,
    required this.resolvedPath,
    required this.exists,
  });
}

class SshCommand {
  final String id;
  final String command;
  final CommandCallback? callback;
  final String? tag;

  SshCommand({
    required this.id,
    required this.command,
    this.callback,
    this.tag,
  });
}

class SshStreamChunk {
  final String executionId;
  final String text;
  final bool isError;
  final bool isDone;

  const SshStreamChunk({
    required this.executionId,
    required this.text,
    this.isError = false,
    this.isDone = false,
  });
}

class SshExecutionResult {
  final String stdout;
  final String stderr;
  final int? exitCode;
  final bool interrupted;

  const SshExecutionResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.interrupted,
  });
}

class SshExecutionHandle {
  final String executionId;
  final Stream<SshStreamChunk> stream;
  final Future<SshExecutionResult> result;

  const SshExecutionHandle({
    required this.executionId,
    required this.stream,
    required this.result,
  });
}

class SshManager {
  SshManager();

  SSHClient? _client;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _errorMessage;
  final Queue<SshCommand> _commandQueue = Queue();
  bool _isProcessingQueue = false;
  Server? _currentServer;
  SystemInfo? _systemInfoCache;
  final Map<String, StreamController<String>> _outputControllers = {};
  final Map<String, SSHSession> _activeExecutions = {};

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get errorMessage => _errorMessage;
  Server? get currentServer => _currentServer;

  Future<bool> connect(Server server) async {
    if (_isConnecting) return false;

    _errorMessage = null;
    _isConnecting = true;

    try {
      if (_isConnected) {
        disconnect();
      }

      final socket = await SSHSocket.connect(server.ip, server.port);

      _client = SSHClient(
        socket,
        username: server.username,
        onPasswordRequest: () => server.password,
      );

      await _client!.authenticated;
      _isConnected = true;
      _currentServer = server;
      _systemInfoCache = null;
      _processQueue();

      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isConnected = false;
      _currentServer = null;
      _debugLog('Connection failed: $e');
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  void disconnect() {
    if (_client != null) {
      try {
        _client!.close();
      } catch (_) {}
      _client = null;
    }
    _isConnected = false;
    _currentServer = null;
    _systemInfoCache = null;
    _commandQueue.clear();
    _isProcessingQueue = false;
    for (final session in _activeExecutions.values) {
      try {
        session.close();
      } catch (_) {}
    }
    _activeExecutions.clear();
    for (final controller in _outputControllers.values) {
      try {
        controller.close();
      } catch (_) {}
    }
    _outputControllers.clear();
  }

  Future<String> executeCommand(String command) async {
    if (!_isConnected || _client == null) {
      throw Exception('SSH connection not established');
    }

    final completer = Completer<String>();
    final resultBuffer = StringBuffer();
    final errorBuffer = StringBuffer();

    try {
      final session = await _client!.execute(command);

      session.stdout.listen(
        (data) {
          resultBuffer.write(utf8.decode(data));
        },
        onError: (e) {
          errorBuffer.write(e.toString());
        },
      );

      session.stderr.listen(
        (data) {
          errorBuffer.write(utf8.decode(data));
        },
      );

      unawaited(() async {
        try {
          await session.done;
          final exitCode = await session.waitForExit(
            timeout: const Duration(milliseconds: 200),
          );
          final stdoutText = resultBuffer.toString();
          final stderrText = errorBuffer.toString().trim();
          final combinedOutput = stderrText.isEmpty
              ? stdoutText
              : (stdoutText.trim().isEmpty ? stderrText : '$stdoutText\n$stderrText');
          if (completer.isCompleted) {
            return;
          }
          if (exitCode == null || exitCode == 0) {
            completer.complete(combinedOutput);
          } else {
            completer.completeError(
              combinedOutput.isEmpty
                  ? 'Command exited with code $exitCode'
                  : combinedOutput,
            );
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError('Command execution failed: $e');
          }
        }
      }());

      return await completer.future;
    } catch (e) {
      throw Exception('Command execution failed: $e');
    }
  }

  Future<String> executeUserCommand(String command) async {
    return executeCommand(_wrapInUserShell(command));
  }

  Future<T> withSftp<T>(Future<T> Function(SftpClient sftp) action) async {
    if (!_isConnected || _client == null) {
      throw Exception('SSH connection not established');
    }

    final sftp = await _client!.sftp();
    try {
      return await action(sftp);
    } finally {
      await sftp.close();
    }
  }

  Future<SshExecutionHandle> executeCommandStream(String command) async {
    return _executeCommandStreamInternal(command);
  }

  Future<SshExecutionHandle> executeUserCommandStream(String command) async {
    return _executeCommandStreamInternal(_wrapInUserShell(command));
  }

  Future<SshExecutionHandle> executePrivilegedCommandStream(
    String command,
  ) async {
    if (_currentServer == null) {
      throw Exception('No active server selected');
    }
    final normalizedCommand = _stripLeadingSudo(command);
    final wrappedCommand = _buildPrivilegedCommand(normalizedCommand);
    return _executeCommandStreamInternal(
      wrappedCommand,
      sanitizeSudoPrompt: true,
    );
  }

  Future<SshExecutionHandle> executePrivilegedUserCommandStream(
    String command,
  ) async {
    return executePrivilegedCommandStream(_wrapInUserShell(command));
  }

  Future<SshExecutionHandle> _executeCommandStreamInternal(
    String command, {
    bool sanitizeSudoPrompt = false,
  }) async {
    if (!_isConnected || _client == null) {
      throw Exception('SSH connection not established');
    }

    final executionId = DateTime.now().microsecondsSinceEpoch.toString();
    final controller = StreamController<SshStreamChunk>.broadcast();
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var interrupted = false;

    final completer = Completer<SshExecutionResult>();
    final session = await _client!.execute(command);
    _activeExecutions[executionId] = session;

    Future<void> closeExecution({int? exitCode}) async {
      if (_activeExecutions.remove(executionId) != null) {
        controller.add(
          SshStreamChunk(executionId: executionId, text: '', isDone: true),
        );
        await controller.close();
        if (!completer.isCompleted) {
          completer.complete(
            SshExecutionResult(
              stdout: stdoutBuffer.toString(),
              stderr: stderrBuffer.toString(),
              exitCode: exitCode,
              interrupted: interrupted,
            ),
          );
        }
      }
    }

    session.stdout.listen(
      (Uint8List data) {
        final text = _sanitizeCommandOutput(
          utf8.decode(data),
          sanitizeSudoPrompt: sanitizeSudoPrompt,
        );
        if (text.isEmpty) {
          return;
        }
        stdoutBuffer.write(text);
        controller.add(SshStreamChunk(executionId: executionId, text: text));
      },
      onError: (Object error) {
        final text = _sanitizeCommandOutput(
          error.toString(),
          sanitizeSudoPrompt: sanitizeSudoPrompt,
        );
        if (text.isEmpty) {
          return;
        }
        stderrBuffer.write(text);
        controller.add(
          SshStreamChunk(executionId: executionId, text: text, isError: true),
        );
      },
    );

    session.stderr.listen((Uint8List data) {
      final text = _sanitizeCommandOutput(
        utf8.decode(data),
        sanitizeSudoPrompt: sanitizeSudoPrompt,
      );
      if (text.isEmpty) {
        return;
      }
      stderrBuffer.write(text);
      controller.add(
        SshStreamChunk(executionId: executionId, text: text, isError: true),
      );
    });

    session.done
        .then((_) async {
          final exitCode = await session.waitForExit(
            timeout: const Duration(milliseconds: 200),
          );
          await closeExecution(exitCode: exitCode);
        })
        .catchError((Object error) async {
          stderrBuffer.write(error.toString());
          if (!controller.isClosed) {
            controller.add(
              SshStreamChunk(
                executionId: executionId,
                text: error.toString(),
                isError: true,
              ),
            );
          }
          await closeExecution();
        });

    controller.onCancel = () async {
      interruptExecution(executionId);
      await closeExecution();
    };

    return SshExecutionHandle(
      executionId: executionId,
      stream: controller.stream,
      result: completer.future,
    );
  }

  void interruptExecution(String executionId) {
    final session = _activeExecutions[executionId];
    if (session == null) {
      return;
    }
    try {
      session.close();
    } catch (_) {}
  }

  Future<String> executePrivilegedCommand(String command) async {
    if (_currentServer == null) {
      throw Exception('No active server selected');
    }
    final wrappedCommand = _buildPrivilegedCommand(command);
    return executeCommand(wrappedCommand);
  }

  Future<String> _executeCommandOrFallback(
    String command,
    String fallback, {
    String? label,
  }) async {
    try {
      final result = await executeCommand(command);
      return result.trim().isEmpty ? fallback : result;
    } catch (e) {
      _debugLog('Command fallback: ${label ?? command} - $e');
      return fallback;
    }
  }

  String _shellSingleQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  String _wrapInUserShell(String command) {
    final trimmed = command.trimLeft();
    if (trimmed.startsWith('bash -lc ') || trimmed.startsWith('bash -ic ')) {
      return command;
    }
    final script =
        'export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$HOME/.local/share/uv/bin:\$PATH"; '
        '[ -f /etc/profile ] && . /etc/profile >/dev/null 2>&1; '
        '[ -f "\$HOME/.profile" ] && . "\$HOME/.profile" >/dev/null 2>&1; '
        '[ -f "\$HOME/.bash_profile" ] && . "\$HOME/.bash_profile" >/dev/null 2>&1; '
        '[ -f "\$HOME/.bashrc" ] && . "\$HOME/.bashrc" >/dev/null 2>&1; '
        '$command';
    return 'bash -lc ${_shellSingleQuote(script)}';
  }

  String _buildPrivilegedCommand(String command) {
    if (_currentServer == null) {
      throw Exception('No active server selected');
    }
    final password = _shellSingleQuote(_currentServer!.password);
    final normalizedCommand = _stripLeadingSudo(command);
    return "printf %s\\\\n $password | sudo -S -p '' $normalizedCommand";
  }

  String _stripLeadingSudo(String command) {
    final trimmedLeft = command.trimLeft();
    if (!trimmedLeft.startsWith('sudo ')) {
      return command;
    }
    return trimmedLeft.substring(5).trimLeft();
  }

  String _sanitizeCommandOutput(
    String text, {
    required bool sanitizeSudoPrompt,
  }) {
    if (!sanitizeSudoPrompt || text.isEmpty) {
      return text;
    }
    return text.replaceAll(
      RegExp(
        r'\[sudo\]\s*password\s*for\s+[^\r\n:]+:\s*',
        caseSensitive: false,
      ),
      '',
    );
  }

  String _normalizeRemotePath(String path) {
    if (path.trim().isEmpty) {
      return '/';
    }

    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (segments.isNotEmpty) {
          segments.removeLast();
        }
        continue;
      }
      segments.add(segment);
    }
    return segments.isEmpty ? '/' : '/${segments.join('/')}';
  }

  Future<String> getLoginDirectory() async {
    final result = await executeCommand("bash -lc 'pwd'");
    return _normalizeRemotePath(result.trim());
  }

  Future<DirectoryResolution> resolveDirectory(
    String? path, {
    bool fallbackToParent = false,
  }) async {
    final normalizedPath = path == null || path.trim().isEmpty
        ? await getLoginDirectory()
        : _normalizeRemotePath(path);
    final quotedPath = _shellSingleQuote(normalizedPath);
    final result = await executeCommand(
      'target=$quotedPath; '
      'if [ -d "\$target" ]; then '
      'printf "OK|%s\\n" "\$target"; '
      'elif [ "${fallbackToParent ? '1' : '0'}" = "1" ]; then '
      'fallback=\$(dirname "\$target"); '
      'while [ "\$fallback" != "/" ] && [ ! -d "\$fallback" ]; do '
      'fallback=\$(dirname "\$fallback"); '
      'done; '
      'if [ -d "\$fallback" ]; then '
      'printf "FALLBACK|%s\\n" "\$fallback"; '
      'else '
      'printf "FALLBACK|/\\n"; '
      'fi; '
      'else '
      'printf "MISSING|%s\\n" "\$target"; '
      'fi',
    );

    final parts = result.trim().split('|');
    final status = parts.isNotEmpty ? parts.first : 'MISSING';
    final resolvedPath = parts.length > 1
        ? _normalizeRemotePath(parts.sublist(1).join('|'))
        : normalizedPath;
    return DirectoryResolution(
      requestedPath: normalizedPath,
      resolvedPath: resolvedPath,
      exists: status != 'MISSING',
    );
  }

  void executeCommandAsync(
    String command, {
    CommandCallback? callback,
    String? tag,
  }) {
    final cmd = SshCommand(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      command: command,
      callback: callback,
      tag: tag,
    );
    _commandQueue.add(cmd);
    _processQueue();
  }

  void executeCommandsBatch(
    List<String> commands, {
    CommandCallback? callback,
    String? tag,
  }) {
    for (final command in commands) {
      executeCommandAsync(command, callback: callback, tag: tag);
    }
  }

  Stream<String> getTerminalOutput(String sessionId) {
    if (!_outputControllers.containsKey(sessionId)) {
      _outputControllers[sessionId] = StreamController<String>.broadcast();
    }
    return _outputControllers[sessionId]!.stream;
  }

  Future<void> executeInteractiveCommand(
    String sessionId,
    String command,
  ) async {
    if (!_isConnected || _client == null) {
      _outputControllers[sessionId]?.addError('SSH connection not established');
      return;
    }

    try {
      final result = await executeCommand(command);
      _outputControllers[sessionId]?.add(result);
    } catch (e) {
      _outputControllers[sessionId]?.addError(e.toString());
    }
  }

  void closeTerminalSession(String sessionId) {
    _outputControllers[sessionId]?.close();
    _outputControllers.remove(sessionId);
  }

  Future<SystemInfo> getSystemInfo() async {
    final profileResult = await _executeCommandOrFallback(
      """bash -lc 'if [ -r /etc/os-release ]; then . /etc/os-release; fi; printf "__OS_ID__|%s\n" "\${ID:-}"; printf "__OS_ID_LIKE__|%s\n" "\${ID_LIKE:-}"; printf "__OS_NAME__|%s\n" "\${NAME:-}"; printf "__OS_PRETTY__|%s\n" "\${PRETTY_NAME:-}"; printf "__OS_VERSION__|%s\n" "\${VERSION_ID:-}"; if command -v apt-get >/dev/null 2>&1; then echo "__CMD__|apt-get"; fi; if command -v dnf >/dev/null 2>&1; then echo "__CMD__|dnf"; fi; if command -v yum >/dev/null 2>&1; then echo "__CMD__|yum"; fi; if command -v zypper >/dev/null 2>&1; then echo "__CMD__|zypper"; fi; if command -v pacman >/dev/null 2>&1; then echo "__CMD__|pacman"; fi; if command -v apk >/dev/null 2>&1; then echo "__CMD__|apk"; fi; if command -v systemctl >/dev/null 2>&1; then echo "__CMD__|systemctl"; fi; if command -v service >/dev/null 2>&1; then echo "__CMD__|service"; fi; if command -v ufw >/dev/null 2>&1; then echo "__CMD__|ufw"; fi; if command -v firewall-cmd >/dev/null 2>&1; then echo "__CMD__|firewall-cmd"; fi; if command -v iptables >/dev/null 2>&1; then echo "__CMD__|iptables"; fi'""",
      '',
      label: 'system-profile',
    );
    final profile = _parseSystemProfile(profileResult);
    final osInfoResult = profile['osInfo']?.trim().isNotEmpty == true
        ? profile['osInfo']!.trim()
        : await _executeCommandOrFallback(
            """bash -lc 'if [ -f /etc/issue ]; then head -1 /etc/issue; else uname -a; fi'""",
            'Unknown',
            label: 'system-os-info-fallback',
          );

    final kernelResult = await _executeCommandOrFallback(
      'uname -r',
      'Unknown',
      label: 'system-kernel',
    );
    final uptimeResult = await _executeCommandOrFallback(
      'uptime -p',
      'Unknown',
      label: 'system-uptime',
    );
    final cpuCoresResult = await _executeCommandOrFallback(
      'nproc',
      '0',
      label: 'system-cpu-cores',
    );
    final memoryResult = await _executeCommandOrFallback(
      'free -h | grep Mem | awk \'{print \$2}\'',
      '0',
      label: 'system-memory-total',
    );
    final diskResult = await _executeCommandOrFallback(
      'df -h / | grep / | awk \'{print \$2}\'',
      '0',
      label: 'system-disk-total',
    );

    final info = SystemInfo(
      osInfo: osInfoResult.trim(),
      osId: profile['osId'] ?? '',
      osName: profile['osName'] ?? '',
      osVersion: profile['osVersion'] ?? '',
      osFamily: profile['osFamily'] ?? '',
      packageManager: profile['packageManager'] ?? '',
      serviceManager: profile['serviceManager'] ?? '',
      firewallBackend: profile['firewallBackend'] ?? '',
      kernelVersion: kernelResult.trim(),
      uptime: uptimeResult.trim(),
      cpuCores: int.tryParse(cpuCoresResult.trim()) ?? 0,
      memoryTotal: memoryResult.trim(),
      diskTotal: diskResult.trim(),
    );

    _systemInfoCache = info;
    return info;
  }

  Future<SystemInfo> _resolvePlatformInfo() async {
    if (_systemInfoCache != null) {
      return _systemInfoCache!;
    }
    final server = _currentServer;
    if (server != null &&
        ((server.packageManager?.trim().isNotEmpty ?? false) ||
            (server.serviceManager?.trim().isNotEmpty ?? false) ||
            (server.firewallBackend?.trim().isNotEmpty ?? false))) {
      return SystemInfo(
        osInfo: server.osInfo ?? 'Unknown',
        osId: server.osId ?? '',
        osName: server.osName ?? '',
        osVersion: server.osVersion ?? '',
        osFamily: server.osFamily ?? '',
        packageManager: server.packageManager ?? '',
        serviceManager: server.serviceManager ?? '',
        firewallBackend: server.firewallBackend ?? '',
        kernelVersion: server.kernelVersion ?? '',
        uptime: server.uptime ?? '',
        cpuCores: 0,
        memoryTotal: '0',
        diskTotal: '0',
      );
    }
    return getSystemInfo();
  }

  Map<String, String> _parseSystemProfile(String raw) {
    final values = <String, String>{};
    final availableCommands = <String>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.contains('|')) {
        continue;
      }
      final separatorIndex = trimmed.indexOf('|');
      final key = trimmed.substring(0, separatorIndex);
      final value = trimmed.substring(separatorIndex + 1).trim();
      switch (key) {
        case '__OS_ID__':
          values['osId'] = value;
          break;
        case '__OS_ID_LIKE__':
          values['idLike'] = value;
          break;
        case '__OS_NAME__':
          values['osName'] = value;
          break;
        case '__OS_PRETTY__':
          values['osInfo'] = value;
          break;
        case '__OS_VERSION__':
          values['osVersion'] = value;
          break;
        case '__CMD__':
          if (value.isNotEmpty) {
            availableCommands.add(value);
          }
          break;
      }
    }
    final osId = values['osId'] ?? '';
    values['osFamily'] = LinuxPlatformSupport.detectFamily(
      osId: osId,
      osInfo: values['osInfo'] ?? values['osName'] ?? '',
      idLike: values['idLike'] ?? '',
    );
    values['packageManager'] = LinuxPlatformSupport.detectPackageManager(
      family: values['osFamily'] ?? 'linux',
      availableCommands: availableCommands,
    );
    values['serviceManager'] = LinuxPlatformSupport.detectServiceManager(
      availableCommands,
    );
    values['firewallBackend'] = LinuxPlatformSupport.detectFirewallBackend(
      availableCommands,
    );
    return values;
  }

  Future<List<ServiceInfo>> _getSysvServiceList() async {
    final result = await executeCommand(
      """bash -lc '(service --status-all 2>/dev/null || chkconfig --list 2>/dev/null) | head -80'""",
    );
    final lines = result.trim().split('\n');
    final services = <ServiceInfo>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final bracketMatch = RegExp(r'^\[\s*([+-?])\s*\]\s+(.+)$').firstMatch(trimmed);
      if (bracketMatch != null) {
        final statusToken = bracketMatch.group(1) ?? '?';
        services.add(
          ServiceInfo(
            name: bracketMatch.group(2)?.trim() ?? trimmed,
            status: statusToken == '+' ? 'running' : 'stopped',
            isEnabled: statusToken == '+',
            description: 'SysV service',
          ),
        );
        continue;
      }
      final chkconfigMatch = RegExp(r'^(\S+)\s+0:(on|off)\s+1:(on|off)\s+2:(on|off)\s+3:(on|off)\s+4:(on|off)\s+5:(on|off)\s+6:(on|off)').firstMatch(trimmed);
      if (chkconfigMatch != null) {
        services.add(
          ServiceInfo(
            name: chkconfigMatch.group(1) ?? trimmed,
            status: 'unknown',
            isEnabled: (chkconfigMatch.group(5) ?? 'off') == 'on',
            description: 'SysV service',
          ),
        );
      }
    }
    return services;
  }

  Future<List<FirewallRule>> _getFirewalldRules() async {
    final portsResult = await executePrivilegedCommand('firewall-cmd --list-ports 2>/dev/null || true');
    final richRulesResult = await executePrivilegedCommand('firewall-cmd --list-rich-rules 2>/dev/null || true');
    final rules = <FirewallRule>[];
    for (final token in portsResult.split(RegExp(r'\s+'))) {
      final trimmed = token.trim();
      if (trimmed.isEmpty || !trimmed.contains('/')) {
        continue;
      }
      final parts = trimmed.split('/');
      rules.add(
        FirewallRule(
          id: 'port:$trimmed',
          action: 'ALLOW',
          protocol: parts.length > 1 ? parts[1].toUpperCase() : 'TCP',
          source: null,
          destination: null,
          port: parts.first,
        ),
      );
    }
    for (final line in richRulesResult.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final sourceMatch = RegExp(r'source address="([^"]+)"').firstMatch(trimmed);
      final portMatch = RegExp(r'port port="([^"]+)"').firstMatch(trimmed);
      final protocolMatch = RegExp(r'protocol="([^"]+)"').firstMatch(trimmed);
      final action = trimmed.contains('reject') || trimmed.contains('drop')
          ? 'DENY'
          : 'ALLOW';
      rules.add(
        FirewallRule(
          id: 'rich:${trimmed.hashCode}',
          action: action,
          protocol: (protocolMatch?.group(1) ?? 'ALL').toUpperCase(),
          source: sourceMatch?.group(1),
          destination: null,
          port: portMatch?.group(1),
        ),
      );
    }
    return rules;
  }

  Future<List<FirewallRule>> _getIptablesRules() async {
    final result = await executePrivilegedCommand('iptables -S INPUT 2>/dev/null || true');
    final rules = <FirewallRule>[];
    for (final line in result.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('-A ')) {
        continue;
      }
      final actionMatch = RegExp(r'-j\s+(\S+)').firstMatch(trimmed);
      final protocolMatch = RegExp(r'-p\s+(\S+)').firstMatch(trimmed);
      final sourceMatch = RegExp(r'-s\s+(\S+)').firstMatch(trimmed);
      final portMatch = RegExp(r'--dport\s+(\S+)').firstMatch(trimmed);
      rules.add(
        FirewallRule(
          id: 'iptables:${trimmed.hashCode}',
          action: (actionMatch?.group(1) ?? 'ALLOW').toUpperCase(),
          protocol: (protocolMatch?.group(1) ?? 'ALL').toUpperCase(),
          source: sourceMatch?.group(1),
          destination: null,
          port: portMatch?.group(1),
        ),
      );
    }
    return rules;
  }

  Future<ResourceUsage> getResourceUsage() async {
    final cpuResult = await _executeCommandOrFallback(
      'LC_ALL=C top -bn1 | grep "Cpu(s)" | sed "s/.*, *\\([0-9.]*\\)%* id.*/\\1/" | awk \'{print 100 - \$1}\'',
      '0',
      label: 'resource-cpu',
    );

    final memoryResult = await _executeCommandOrFallback(
      'free -h | grep Mem',
      'Mem: 0 0 0 0 0 0',
      label: 'resource-memory',
    );

    final diskResult = await _executeCommandOrFallback(
      'df -h / | grep /',
      'rootfs 0 0 0 0% /',
      label: 'resource-disk',
    );

    final networkResult = await _executeCommandOrFallback(
      "bash -lc 'iface=\$(ip route 2>/dev/null | awk \"/^default/ {print \\\$5; exit}\"); "
          'if [ -z "\$iface" ]; then '
          "iface=\$(awk -F: 'NR>2 {gsub(/ /, \"\", \$1); if (\$1 !~ /^(lo|docker|veth|br-|virbr)/) {print \$1; exit}}' /proc/net/dev); "
          'fi; '
          'if [ -n "\$iface" ] && [ -r "/sys/class/net/\$iface/statistics/tx_bytes" ]; then '
          'tx=\$(cat "/sys/class/net/\$iface/statistics/tx_bytes"); '
          'rx=\$(cat "/sys/class/net/\$iface/statistics/rx_bytes"); '
          'printf "TX:%s RX:%s" "\$tx" "\$rx"; '
          'else printf "TX:0 RX:0"; fi\'',
      'TX:0 RX:0',
      label: 'resource-network',
    );

    final connectionsResult = await _executeCommandOrFallback(
      'ss -tuln | wc -l',
      '0',
      label: 'resource-connections',
    );
    final gpuDevices = await _collectGpuDevices();

    final cpuUsage = double.tryParse(cpuResult.trim()) ?? 0.0;

    final memoryParts = memoryResult.trim().split(RegExp(r'\s+'));
    final memoryUsed = memoryParts.length > 2 ? memoryParts[2] : '0';
    final memoryTotal = memoryParts.length > 1 ? memoryParts[1] : '0';
    final memoryUsedBytes = memoryParts.length > 2
        ? _parseSizeToBytes(memoryParts[2])
        : 0.0;
    final memoryTotalBytes = memoryParts.length > 1
        ? _parseSizeToBytes(memoryParts[1])
        : 0.0;
    final double memoryPercent = memoryTotalBytes > 0
        ? (memoryUsedBytes / memoryTotalBytes * 100.0)
        : 0.0;

    final diskParts = diskResult.trim().split(RegExp(r'\s+'));
    final diskTotal = diskParts.length > 1 ? diskParts[1] : '0';
    final diskUsed = diskParts.length > 2 ? diskParts[2] : '0';
    final diskPercent =
        double.tryParse(
          diskParts.length > 4 ? diskParts[4].replaceAll('%', '') : '0',
        ) ??
        0;

    final uploadBytes = networkResult.contains('TX:')
        ? int.tryParse(networkResult.split('TX:')[1].split(' ')[0].trim()) ?? 0
        : 0;
    final downloadBytes = networkResult.contains('RX:')
        ? int.tryParse(networkResult.split('RX:')[1].trim()) ?? 0
        : 0;

    final usage = ResourceUsage(
      cpuUsage: cpuUsage.clamp(0.0, 100.0),
      memoryUsed: memoryUsed,
      memoryTotal: memoryTotal,
      memoryPercent: memoryPercent.clamp(0.0, 100.0),
      diskUsed: diskUsed,
      diskTotal: diskTotal,
      diskPercent: diskPercent.clamp(0.0, 100.0),
      networkUpload: _formatBytes(uploadBytes),
      networkDownload: _formatBytes(downloadBytes),
      activeConnections: int.tryParse(connectionsResult.trim()) ?? 0,
      gpuDevices: gpuDevices,
    );

    return usage;
  }

  double _parseSizeToBytes(String input) {
    final normalized = input.trim();
    final match = RegExp(
      r'^([0-9]+(?:\.[0-9]+)?)([KMGTP]?i?B?)?$',
    ).firstMatch(normalized);
    if (match == null) {
      return 0.0;
    }

    final value = double.tryParse(match.group(1) ?? '') ?? 0.0;
    final unit = (match.group(2) ?? '').toUpperCase();
    const factors = <String, double>{
      '': 1,
      'B': 1,
      'K': 1024,
      'KB': 1024,
      'KI': 1024,
      'KIB': 1024,
      'M': 1024 * 1024,
      'MB': 1024 * 1024,
      'MI': 1024 * 1024,
      'MIB': 1024 * 1024,
      'G': 1024 * 1024 * 1024,
      'GB': 1024 * 1024 * 1024,
      'GI': 1024 * 1024 * 1024,
      'GIB': 1024 * 1024 * 1024,
      'T': 1024 * 1024 * 1024 * 1024,
      'TB': 1024 * 1024 * 1024 * 1024,
      'TI': 1024 * 1024 * 1024 * 1024,
      'TIB': 1024 * 1024 * 1024 * 1024,
      'P': 1024 * 1024 * 1024 * 1024 * 1024,
      'PB': 1024 * 1024 * 1024 * 1024 * 1024,
      'PI': 1024 * 1024 * 1024 * 1024 * 1024,
      'PIB': 1024 * 1024 * 1024 * 1024 * 1024,
    };

    return value * (factors[unit] ?? 1);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final fractionDigits = value >= 100
        ? 0
        : value >= 10
        ? 1
        : 2;
    return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }

  String _formatMegaBytes(num valueInMb) {
    final valueInGb = valueInMb / 1024.0;
    if (valueInGb >= 100) {
      return '${valueInGb.toStringAsFixed(0)} GiB';
    }
    if (valueInGb >= 10) {
      return '${valueInGb.toStringAsFixed(1)} GiB';
    }
    return '${valueInGb.toStringAsFixed(2)} GiB';
  }

  Future<List<GpuDeviceUsage>> _collectGpuDevices() async {
    final nvidiaRaw = await _executeCommandOrFallback(
      "bash -lc 'if command -v nvidia-smi >/dev/null 2>&1; then "
          "nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu "
          "--format=csv,noheader,nounits 2>/dev/null; fi'",
      '',
      label: 'resource-gpu-nvidia',
    );
    final nvidiaDevices = _parseNvidiaGpuDevices(nvidiaRaw);
    if (nvidiaDevices.isNotEmpty) {
      return nvidiaDevices;
    }

    final inventoryRaw = await _executeCommandOrFallback(
      "bash -lc 'if command -v lspci >/dev/null 2>&1; then "
          "lspci | grep -Ei \"VGA compatible controller|3D controller|Display controller\"; fi'",
      '',
      label: 'resource-gpu-inventory',
    );
    return _parseGenericGpuInventory(inventoryRaw);
  }

  List<GpuDeviceUsage> _parseNvidiaGpuDevices(String raw) {
    final devices = <GpuDeviceUsage>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final parts = trimmed.split(',');
      if (parts.length < 6) {
        continue;
      }
      final index = int.tryParse(parts[0].trim()) ?? devices.length;
      final name = parts[1].trim();
      final utilization = double.tryParse(parts[2].trim()) ?? 0.0;
      final memoryUsedMb = double.tryParse(parts[3].trim()) ?? 0.0;
      final memoryTotalMb = double.tryParse(parts[4].trim()) ?? 0.0;
      final memoryPercent = memoryTotalMb > 0
          ? (memoryUsedMb / memoryTotalMb * 100.0)
          : 0.0;
      final temperature = parts[5].trim().isEmpty ? null : '${parts[5].trim()} C';
      devices.add(
        GpuDeviceUsage(
          index: index,
          vendor: 'nvidia',
          name: name,
          utilizationPercent: utilization.clamp(0.0, 100.0),
          memoryUsed: _formatMegaBytes(memoryUsedMb),
          memoryTotal: _formatMegaBytes(memoryTotalMb),
          memoryPercent: memoryPercent.clamp(0.0, 100.0),
          temperature: temperature,
        ),
      );
    }
    return devices;
  }

  List<GpuDeviceUsage> _parseGenericGpuInventory(String raw) {
    final devices = <GpuDeviceUsage>[];
    var index = 0;
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final lower = trimmed.toLowerCase();
      String vendor;
      if (lower.contains('nvidia')) {
        vendor = 'nvidia';
      } else if (lower.contains('intel')) {
        vendor = 'intel';
      } else if (lower.contains('amd') || lower.contains('advanced micro devices')) {
        vendor = 'amd';
      } else {
        vendor = 'unknown';
      }
      final name = trimmed.contains(':')
          ? trimmed.substring(trimmed.indexOf(':') + 1).trim()
          : trimmed;
      devices.add(
        GpuDeviceUsage(
          index: index,
          vendor: vendor,
          name: name,
          utilizationPercent: 0,
          memoryUsed: '--',
          memoryTotal: vendor == 'intel' ? '共享内存' : '--',
          memoryPercent: 0,
          note: vendor == 'intel'
              ? '已识别 Intel GPU；当前未检测到可读取显存占用的工具'
              : '已识别 GPU 设备；当前未检测到可读取实时显存占用的工具',
        ),
      );
      index++;
    }
    return devices;
  }

  Future<List<ProcessInfo>> getProcessList() async {
    final result = await executeCommand(
      'ps aux --sort=-%cpu | head -21 | tail -20',
    );

    final lines = result.trim().split('\n');
    final processes = <ProcessInfo>[];

    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 11) {
        processes.add(
          ProcessInfo(
            pid: int.tryParse(parts[1]) ?? 0,
            name: parts[10],
            cpuPercent: double.tryParse(parts[2]) ?? 0,
            memoryPercent: double.tryParse(parts[3]) ?? 0,
            status: parts[7],
            user: parts[0],
            command: line.substring(line.indexOf(parts[10])),
          ),
        );
      }
    }

    return processes;
  }

  Future<List<PortInfo>> getPortList() async {
    final result = await executeCommand('ss -tulnpH');

    final lines = result.trim().split('\n');
    final ports = <PortInfo>[];

    for (final line in lines) {
      if (line.isEmpty || line.startsWith('State')) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 6) {
        final protocol = parts[0];
        final address = parts[4];
        final portParts = address.split(':');
        final port = portParts.isNotEmpty ? portParts.last : '';

        String pid = '';
        String processName = '';
        final processPart = parts.length > 6 ? parts.sublist(6).join(' ') : '';
        final pidMatch = RegExp(r'pid=(\d+)').firstMatch(processPart);
        final nameMatch = RegExp(r'"([^"]+)"').firstMatch(processPart);
        if (pidMatch != null) {
          pid = pidMatch.group(1) ?? '';
        }
        if (nameMatch != null) {
          processName = nameMatch.group(1) ?? '';
        }

        ports.add(
          PortInfo(
            port: port,
            protocol: protocol.contains('tcp') ? 'TCP' : 'UDP',
            pid: pid,
            processName: processName,
            address: address,
          ),
        );
      }
    }

    return ports;
  }

  Future<List<FirewallRule>> getFirewallRules() async {
    final systemInfo = await _resolvePlatformInfo();
    if (systemInfo.firewallBackend == 'firewalld') {
      return _getFirewalldRules();
    }
    if (systemInfo.firewallBackend == 'iptables') {
      return _getIptablesRules();
    }
    final result = await executePrivilegedCommand('ufw status numbered 2>/dev/null');

    final lines = result.trim().split('\n');
    final rules = <FirewallRule>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('Status:')) continue;

      final match = RegExp(
        r'^\[\s*(\d+)\]\s+(.+?)\s+(ALLOW|DENY|REJECT)\s+IN\s+(.+)$',
      ).firstMatch(trimmed);
      if (match == null) {
        continue;
      }

      final target = match.group(2)?.trim() ?? '';
      final action = match.group(3)?.trim() ?? 'ALLOW';
      final source = match.group(4)?.trim();
      String protocol = 'ALL';
      String? port;

      if (target.contains('/')) {
        final targetParts = target.split('/');
        port = targetParts.first.trim();
        protocol = targetParts.last.trim().toUpperCase();
      } else if (RegExp(r'^\d+$').hasMatch(target)) {
        port = target;
      }

      rules.add(
        FirewallRule(
          id: match.group(1)!,
          action: action,
          protocol: protocol,
          source: source == 'Anywhere' ? null : source,
          destination: null,
          port: port,
        ),
      );
    }

    return rules;
  }

  Future<bool> getFirewallEnabled() async {
    final systemInfo = await _resolvePlatformInfo();
    switch (systemInfo.firewallBackend) {
      case 'firewalld':
        final result = await executePrivilegedCommand('firewall-cmd --state 2>/dev/null || true');
        return result.toLowerCase().contains('running');
      case 'iptables':
        final result = await executePrivilegedCommand('iptables -S 2>/dev/null || true');
        return result.trim().isNotEmpty;
      case 'none':
        return false;
      default:
        final result = await executePrivilegedCommand(
          'ufw status 2>/dev/null | grep -i status',
        );
        return result.toLowerCase().contains('active');
    }
  }

  Future<String> manageFirewall({
    required String action,
    String? port,
    String? protocol,
    String? source,
    String? ruleNumber,
    String? ruleAction,
  }) async {
    final systemInfo = await _resolvePlatformInfo();
    late final String command;
    switch (systemInfo.firewallBackend) {
      case 'firewalld':
        command = LinuxPlatformSupport.buildFirewalldCommand(
          action: action,
          port: port,
          protocol: protocol,
          source: source,
          ruleAction: ruleAction,
        );
        break;
      case 'ufw':
      case 'none':
      case 'iptables':
      default:
        command = LinuxPlatformSupport.buildUfwCommand(
          action: action,
          port: port,
          protocol: protocol,
          source: source,
          ruleNumber: ruleNumber,
          ruleAction: ruleAction,
        );
        break;
    }
    return await executePrivilegedCommand(command);
  }

  Future<List<ServiceInfo>> getServiceList() async {
    final systemInfo = await _resolvePlatformInfo();
    if (systemInfo.serviceManager != 'systemd') {
      return _getSysvServiceList();
    }
    final result = await executeCommand(
      """bash -lc 'systemctl list-units --type=service --all --no-pager --no-legend 2>/dev/null | head -80 | while read -r unit load active sub description; do enabled=\$(systemctl is-enabled "\$unit" 2>/dev/null || echo disabled); echo "\$unit|\$active|\$enabled|\$description"; done'""",
    );

    final lines = result.trim().split('\n');
    final services = <ServiceInfo>[];

    for (final line in lines) {
      if (line.isEmpty) continue;
      final parts = line.split('|');
      if (parts.length >= 4) {
        final name = parts[0].trim().replaceAll('.service', '');
        final status = parts[1].trim();
        final enabledState = parts[2].trim();
        services.add(
          ServiceInfo(
            name: name,
            status: status,
            isEnabled: enabledState == 'enabled',
            description: parts.sublist(3).join('|').trim(),
          ),
        );
      }
    }

    return services;
  }

  Future<String> manageService({
    required String serviceName,
    required String action,
  }) async {
    final systemInfo = await _resolvePlatformInfo();
    final command = LinuxPlatformSupport.buildServiceCommand(
      serviceManager: systemInfo.serviceManager,
      serviceName: serviceName,
      action: action,
    );
    return await executePrivilegedCommand(command);
  }

  Future<String> getServiceLogs(String serviceName, {int lines = 80}) async {
    final systemInfo = await _resolvePlatformInfo();
    return executePrivilegedCommand(
      LinuxPlatformSupport.buildServiceLogCommand(
        serviceManager: systemInfo.serviceManager,
        serviceName: serviceName,
        lines: lines,
      ),
    );
  }

  Future<String> createManagedService({
    required String serviceName,
    required String execStart,
    required String workingDirectory,
    required String description,
    String? arguments,
    String? logPath,
  }) async {
    final systemInfo = await _resolvePlatformInfo();
    if (systemInfo.serviceManager != 'systemd') {
      throw Exception('当前服务器未检测到 systemd，暂不支持自动创建托管服务');
    }
    final safeServiceName = serviceName.trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final execLine = arguments == null || arguments.trim().isEmpty
        ? execStart.trim()
        : '${execStart.trim()} ${arguments.trim()}';
    final logDirective = logPath != null && logPath.trim().isNotEmpty
        ? '\nStandardOutput=append:${logPath.trim()}\nStandardError=append:${logPath.trim()}'
        : '';
    final serviceContent =
        '''
[Unit]
Description=${description.trim().isEmpty ? safeServiceName : description.trim()}
After=network.target

[Service]
Type=simple
WorkingDirectory=${workingDirectory.trim()}
ExecStart=$execLine
Restart=always$logDirective

[Install]
WantedBy=multi-user.target
''';

    final encoded = base64.encode(utf8.encode(serviceContent));
    final targetPath = '/etc/systemd/system/$safeServiceName.service';
    final command =
        'printf %s "$encoded" | base64 -d | sudo tee "$targetPath" > /dev/null && sudo systemctl daemon-reload && sudo systemctl enable --now $safeServiceName.service';
    return executePrivilegedCommand(command.replaceFirst('sudo ', ''));
  }

  Future<List<DockerContainer>> getDockerContainers() async {
    final installed = await isDockerInstalled();
    if (!installed) {
      return [];
    }

    final result = await executePrivilegedCommand(
      'docker ps -a --format "{{.ID}}|{{.Names}}|{{.Status}}|{{.Image}}|{{.Ports}}" 2>/dev/null',
    );

    if (result.trim().isEmpty) {
      return [];
    }

    final lines = result.trim().split('\n');
    final containers = <DockerContainer>[];
    final statsResult = await executePrivilegedCommand(
      'docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}" 2>/dev/null || true',
    );
    final stats = <String, List<String>>{};
    for (final line in statsResult.trim().split('\n')) {
      final parts = line.split('|');
      if (parts.length >= 3) {
        stats[parts[0]] = [parts[1], parts[2]];
      }
    }

    for (final line in lines) {
      final parts = line.split('|');
      if (parts.length >= 5) {
        final containerStats = stats[parts[1]];
        containers.add(
          DockerContainer(
            id: parts[0].substring(0, 12),
            name: parts[1],
            status: parts[2],
            image: parts[3],
            ports: parts[4]
                .split(',')
                .map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .toList(),
            cpuUsage: containerStats?[0] ?? '-',
            memoryUsage: containerStats?[1] ?? '-',
          ),
        );
      }
    }
    return containers;
  }

  Future<String> manageContainer({
    required String containerId,
    required String action,
  }) async {
    final command = 'docker $action $containerId';
    return await executePrivilegedCommand(command.replaceFirst('sudo ', ''));
  }

  Future<List<DockerImage>> getDockerImages() async {
    final installed = await isDockerInstalled();
    if (!installed) {
      return [];
    }

    final result = await executePrivilegedCommand(
      'docker images --format "{{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedSince}}" 2>/dev/null',
    );

    if (result.trim().isEmpty) {
      return [];
    }

    final lines = result.trim().split('\n');
    final images = <DockerImage>[];

    for (final line in lines) {
      final parts = line.split('|');
      if (parts.length >= 5) {
        images.add(
          DockerImage(
            id: parts[0].substring(0, 12),
            name: parts[1],
            tag: parts[2],
            size: parts[3],
            created: parts[4],
          ),
        );
      }
    }
    return images;
  }

  Future<bool> isDockerInstalled() async {
    final result = await executeCommand(
      'docker --version >/dev/null 2>&1 && echo INSTALLED || echo MISSING',
    );
    return result.trim() == 'INSTALLED';
  }

  Future<String> deleteImage({required String imageId}) async {
    final command = 'docker rmi $imageId';
    return await executeCommand(command);
  }

  Future<FileListResult> listFilesSnapshot(String path) async {
    final resolution = await resolveDirectory(path, fallbackToParent: true);
    final quotedPath = _shellSingleQuote(resolution.resolvedPath);
    final result = await executeCommand(
      'target=$quotedPath; '
      'printf "__PATH__|%s\\n" "\$target"; '
      'find "\$target" -maxdepth 1 -mindepth 1 -printf "%f|%y|%s|%TY-%Tm-%Td %TH:%TM|%M\\n" 2>/dev/null | sort',
    );

    final lines = result.trim().split('\n');
    final files = <FileInfo>[];
    var resolvedPath = resolution.resolvedPath;

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith('__PATH__|')) {
        resolvedPath = _normalizeRemotePath(line.substring('__PATH__|'.length));
        continue;
      }
      final parts = line.split('|');
      if (parts.length >= 5) {
        final fileName = parts[0];
        files.add(
          FileInfo(
            name: fileName,
            path: resolvedPath == '/'
                ? '/$fileName'
                : '$resolvedPath/$fileName',
            isDirectory: parts[1] == 'd',
            size: parts[2],
            modified: parts[3],
            permissions: parts[4],
          ),
        );
      }
    }

    return FileListResult(files: files, resolvedPath: resolvedPath);
  }

  Future<List<FileInfo>> listFiles(String path) async {
    final result = await listFilesSnapshot(path);
    return result.files;
  }

  Future<String> createDirectory(String path) async {
    return await executeCommand('mkdir -p "$path"');
  }

  Future<String> deleteFile(String path) async {
    return await executeCommand('rm -rf "$path"');
  }

  Future<String> renameFile(String oldPath, String newPath) async {
    return await executeCommand('mv "$oldPath" "$newPath"');
  }

  Future<String> readFile(String path) async {
    return await executeCommand('cat "$path" 2>/dev/null');
  }

  Future<String> writeFile(String path, String content) async {
    if (content.isEmpty) {
      return executeCommand(': > "$path"');
    }

    final encoded = base64.encode(utf8.encode(content));
    return executeCommand('printf %s "$encoded" | base64 -d > "$path"');
  }

  Future<int?> statRemoteFileSize(String remotePath) async {
    return withSftp((sftp) async {
      final stat = await sftp.stat(remotePath);
      return stat.size;
    });
  }

  Future<void> uploadLocalFile(
    String localPath,
    String remotePath, {
    void Function(int bytesWritten)? onProgress,
    TransferCancellationToken? cancelToken,
  }) async {
    cancelToken?._throwIfCancelled();
    final sftp = await _client!.sftp();
    dynamic writer;
    SftpFile? remoteFile;
    cancelToken?._bind(() async {
      try {
        await writer?.abort();
      } catch (_) {}
      try {
        await remoteFile?.close();
      } catch (_) {}
      await sftp.close();
    });
    try {
      remoteFile = await sftp.open(
        remotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      try {
        cancelToken?._throwIfCancelled();
        writer = remoteFile.write(
          File(localPath).openRead().cast<Uint8List>(),
          onProgress: onProgress,
        );
        await writer.done;
        cancelToken?._throwIfCancelled();
      } finally {
        await remoteFile.close();
      }
    } catch (error) {
      if (_isTransferCancelledError(error, cancelToken)) {
        throw const TransferCancelledException();
      }
      rethrow;
    } finally {
      try {
        await sftp.close();
      } catch (_) {}
    }
  }

  Future<void> downloadRemoteFile(
    String remotePath,
    String localPath, {
    void Function(int bytesRead)? onProgress,
    TransferCancellationToken? cancelToken,
  }) async {
    final targetFile = File(localPath);
    await targetFile.parent.create(recursive: true);
    cancelToken?._throwIfCancelled();
    final randomAccessFile = await targetFile.open(mode: FileMode.write);
    final sftp = await _client!.sftp();
    SftpFile? remoteFile;
    var cancelledByToken = false;
    cancelToken?._bind(() async {
      cancelledByToken = true;
      // Abort the SFTP session first so pending reads fail immediately.
      try {
        await sftp.close();
      } catch (_) {}
      try {
        await randomAccessFile.close();
      } catch (_) {}
    });
    try {
      remoteFile = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
      cancelToken?._throwIfCancelled();
      await remoteFile.downloadToRandomAccess(
        randomAccessFile,
        onProgress: (bytesRead) {
          if (cancelToken?.isCancelled ?? false) {
            throw const TransferCancelledException();
          }
          onProgress?.call(bytesRead);
        },
      );
      cancelToken?._throwIfCancelled();
    } catch (error) {
      if (_isTransferCancelledError(error, cancelToken)) {
        throw const TransferCancelledException();
      }
      rethrow;
    } finally {
      try {
        if (!cancelledByToken) {
          await remoteFile?.close();
        }
      } catch (_) {}
      try {
        await randomAccessFile.close();
      } catch (_) {}
      try {
        await sftp.close();
      } catch (_) {}
    }
  }

  Future<String> getCurrentDirectory() async {
    return await executeCommand('pwd');
  }

  Future<bool> checkConnection() async {
    if (!_isConnected || _client == null) {
      return false;
    }
    try {
      await executeCommand('echo "OK"');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> installTool(String toolName) async {
    final systemInfo = await _resolvePlatformInfo();
    final command = LinuxPlatformSupport.buildInstallCommand(
      packageManager: systemInfo.packageManager,
      toolName: toolName,
    );
    return await executePrivilegedCommand(command);
  }

  Future<bool> checkToolInstalled(String toolName) async {
    String command;
    switch (toolName) {
      case 'net-tools':
        command =
            "sh -lc 'if command -v ifconfig >/dev/null 2>&1 || command -v netstat >/dev/null 2>&1; then echo installed; fi'";
        break;
      case 'iproute2':
        command =
            "sh -lc 'if command -v ip >/dev/null 2>&1; then echo installed; fi'";
        break;
      case 'pip':
        command =
            "sh -lc 'if command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1; then echo installed; fi'";
        break;
      case 'nodejs':
        command =
            "sh -lc 'if command -v node >/dev/null 2>&1 || command -v nodejs >/dev/null 2>&1; then echo installed; fi'";
        break;
      case 'ufw':
        command =
            "sh -lc 'if command -v ufw >/dev/null 2>&1 || command -v firewall-cmd >/dev/null 2>&1; then echo installed; fi'";
        break;
      case 'uv':
        command =
            "sh -lc 'if command -v uv >/dev/null 2>&1 || [ -x \"\$HOME/.local/bin/uv\" ]; then echo installed; fi'";
        break;
      default:
        command =
            "sh -lc 'if command -v $toolName >/dev/null 2>&1; then echo installed; fi'";
    }
    final result = await executeCommand(command);
    return result.trim().contains('installed');
  }

  void _processQueue() async {
    if (_isProcessingQueue || !_isConnected || _commandQueue.isEmpty) {
      return;
    }

    _isProcessingQueue = true;

    while (_commandQueue.isNotEmpty && _isConnected) {
      final cmd = _commandQueue.removeFirst();
      try {
        final result = await executeCommand(cmd.command);
        cmd.callback?.call(result, null);
        _debugLog('Command completed: ${cmd.tag ?? cmd.id}');
      } catch (e) {
        cmd.callback?.call('', e.toString());
        _debugLog('Command failed: ${cmd.tag ?? cmd.id} - $e');
      }
    }

    _isProcessingQueue = false;
  }

  void _debugLog(String message) {
    debugPrint('[SshManager] $message');
  }

  bool _isTransferCancelledError(
    Object error,
    TransferCancellationToken? cancelToken,
  ) {
    if (error is TransferCancelledException) {
      return true;
    }
    if (!(cancelToken?.isCancelled ?? false)) {
      return false;
    }
    final raw = error.toString().toLowerCase();
    return raw.contains('connection closed') ||
        raw.contains('file is closed') ||
        raw.contains('abort');
  }
}

extension on TransferCancellationToken {
  void _throwIfCancelled() {
    if (isCancelled) {
      throw const TransferCancelledException();
    }
  }

  void _bind(Future<void> Function() callback) {
    bind(callback);
  }
}
