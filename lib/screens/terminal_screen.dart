import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/adaptive_page_layout.dart';
import '../widgets/app_button_styles.dart';
import '../models/server.dart';

class _TerminalServerState {
  final List<String> outputLines;
  final String draftCommand;
  final int historyCursor;
  final String historyDraft;

  const _TerminalServerState({
    required this.outputLines,
    required this.draftCommand,
    required this.historyCursor,
    required this.historyDraft,
  });
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _commandController = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _commandFocusNode = FocusNode();
  final List<String> _outputLines = [];
  final Map<String, _TerminalServerState> _serverStates = {};
  List<OperationLog> _history = [];
  bool _isLoading = false;
  String? _lastServerId;
  int _historyCursor = -1;
  String _historyDraft = '';

  @override
  void initState() {
    super.initState();
    _commandController.addListener(_cacheCurrentServerState);
    _resetTerminalOutput();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = Provider.of<AppProvider>(context, listen: false);
      _handleServerChanged(provider.selectedServer);
    });
  }

  Future<void> _loadHistory({String? serverId}) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final targetServerId = serverId ?? provider.selectedServer?.id;
    if (targetServerId == null) {
      if (!mounted) return;
      setState(() {
        _history = [];
      });
      return;
    }
    final logs = await provider.loadRecentLogs(limit: 8);
    if (!mounted) return;
    if (provider.selectedServer?.id != targetServerId) {
      return;
    }
    setState(() {
      _history = logs;
    });
  }

  Future<void> _executeCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;

    final provider = Provider.of<AppProvider>(context, listen: false);
    final terminalReady = await provider.ensureTerminalConnection();
    if (!terminalReady) {
      setState(() {
        _outputLines.add('错误: 未连接到服务器');
        _outputLines.add('');
      });
      _cacheCurrentServerState();
      _commandController.clear();
      return;
    }

    setState(() {
      _outputLines.add('\$ $command');
      _isLoading = true;
      _historyCursor = -1;
      _historyDraft = '';
    });
    _commandController.clear();
    _scrollToBottom();

    try {
      final result = await provider.sshManager.executeUserCommand(command);
      await provider.saveOperationLog(command: command, result: result);
      setState(() {
        if (result.isNotEmpty) {
          _outputLines.addAll(result.split('\n'));
        }
        _outputLines.add('');
        _isLoading = false;
      });
    } catch (e) {
      await provider.saveOperationLog(command: command, result: e.toString());
      setState(() {
        _outputLines.add('错误: ${e.toString()}');
        _outputLines.add('');
        _isLoading = false;
      });
    }
    _cacheCurrentServerState();
    await _loadHistory();
    _scrollToBottom();
  }

  void _cacheCurrentServerState() {
    if (_lastServerId == null) {
      return;
    }
    _serverStates[_lastServerId!] = _TerminalServerState(
      outputLines: List<String>.from(_outputLines),
      draftCommand: _commandController.text,
      historyCursor: _historyCursor,
      historyDraft: _historyDraft,
    );
  }

  void _clearCurrentTerminalOutput(Server? server) {
    _commandController.clear();
    _historyCursor = -1;
    _historyDraft = '';
    _resetTerminalOutput(server: server);
    _cacheCurrentServerState();
    setState(() {});
  }

  void _resetTerminalOutput({Server? server}) {
    _outputLines
      ..clear()
      ..add('欢迎使用 ShellGuard 终端')
      ..add(
        server == null
            ? '连接到服务器后即可执行命令'
            : '当前服务器: ${server.name} (${server.ip})',
      )
      ..add('');
  }

  void _handleServerChanged(Server? server) {
    if (_lastServerId == server?.id) {
      return;
    }
    if (_lastServerId != null) {
      _serverStates[_lastServerId!] = _TerminalServerState(
        outputLines: List<String>.from(_outputLines),
        draftCommand: _commandController.text,
        historyCursor: _historyCursor,
        historyDraft: _historyDraft,
      );
    }
    _lastServerId = server?.id;
    final cachedState = server == null ? null : _serverStates[server.id];
    if (cachedState != null) {
      _outputLines
        ..clear()
        ..addAll(cachedState.outputLines);
      _commandController.text = cachedState.draftCommand;
      _commandController.selection = TextSelection.fromPosition(
        TextPosition(offset: _commandController.text.length),
      );
      _historyCursor = cachedState.historyCursor;
      _historyDraft = cachedState.historyDraft;
    } else {
      _commandController.clear();
      _historyCursor = -1;
      _historyDraft = '';
      _resetTerminalOutput(server: server);
    }
    _history = [];
    _isLoading = false;
    _loadHistory(serverId: server?.id);
    if (mounted) {
      setState(() {});
    }
  }

  void _applyHistoryCommand(String command) {
    _commandController.text = command;
    _commandController.selection = TextSelection.fromPosition(
      TextPosition(offset: command.length),
    );
    _cacheCurrentServerState();
    _commandFocusNode.requestFocus();
  }

  void _navigateHistory(int offset) {
    if (_history.isEmpty) {
      return;
    }
    final commands = <String>[];
    for (final log in _history) {
      if (!commands.contains(log.command)) {
        commands.add(log.command);
      }
    }
    if (commands.isEmpty) {
      return;
    }
    if (_historyCursor == -1) {
      _historyDraft = _commandController.text;
    }
    final nextCursor = _historyCursor + offset;
    if (nextCursor < 0) {
      _historyCursor = -1;
      _applyHistoryCommand(_historyDraft);
      return;
    }
    if (nextCursor >= commands.length) {
      return;
    }
    _historyCursor = nextCursor;
    _applyHistoryCommand(commands[_historyCursor]);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    if (_lastServerId != provider.selectedServer?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleServerChanged(provider.selectedServer);
      });
    }

    return AdaptivePageLayout(
      backgroundColor: const Color(0xFF1e1e1e),
      estimatedReservedHeight: 230,
      minBodyHeight: 220,
      header: [
        Row(
          children: [
            const Spacer(),
            TextButton.icon(
              onPressed: provider.selectedServer == null
                  ? null
                  : () => _clearCurrentTerminalOutput(provider.selectedServer),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('清除历史'),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0d0d0d),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        padding: const EdgeInsets.all(16),
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _outputLines.length,
          itemBuilder: (context, index) {
            return Text(
              _outputLines[index],
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'Monospace',
                color: Color(0xFFd4d4d4),
              ),
            );
          },
        ),
      ),
      footer: [
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0d0d0d),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Text(
                '\$',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Monospace',
                  color: Color(0xFF4ec9b0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _navigateHistory(1);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _navigateHistory(-1);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _commandController,
                    focusNode: _commandFocusNode,
                    decoration: AppFieldStyles.toolbarInput(
                      hintText: '输入命令...',
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'Monospace',
                      color: Colors.white,
                    ),
                    onSubmitted: (_) => _executeCommand(),
                    enabled: provider.selectedServer != null && !_isLoading,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF2563eb))
              else
                ElevatedButton(
                  onPressed: provider.selectedServer != null
                      ? _executeCommand
                      : null,
                  style: AppButtonStyles.primary(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('执行'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildHistory(),
      ],
    );
  }

  Widget _buildHistory() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0d0d0d),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最近 7 天命令日志',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFd4d4d4),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const Text(
              '暂无命令记录',
              style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
            )
          else
            ..._history.map((log) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onDoubleTap: () => _applyHistoryCommand(log.command),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          log.command,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontFamily: 'Monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${log.timestamp.month.toString().padLeft(2, '0')}-${log.timestamp.day.toString().padLeft(2, '0')} ${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6b7c93),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _commandController.removeListener(_cacheCurrentServerState);
    _commandController.dispose();
    _scrollController.dispose();
    _commandFocusNode.dispose();
    super.dispose();
  }
}
