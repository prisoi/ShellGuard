import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/server.dart';
import '../providers/app_provider.dart';
import '../widgets/adaptive_page_layout.dart';
import '../widgets/app_button_styles.dart';

class _TerminalBootstrapData {
  final String host;
  final String currentPath;
  final String shell;
  final String openedAt;
  final String kernel;
  final String uptime;

  const _TerminalBootstrapData({
    required this.host,
    required this.currentPath,
    required this.shell,
    required this.openedAt,
    required this.kernel,
    required this.uptime,
  });
}

class _TerminalCommandResult {
  final String output;
  final String currentPath;

  const _TerminalCommandResult({
    required this.output,
    required this.currentPath,
  });
}

class _TerminalTabSession {
  final String id;
  String title;
  List<String> outputLines;
  List<String> commandHistory;
  String draftCommand = '';
  String historyDraft = '';
  int historyCursor = -1;
  bool isBusy = false;
  String currentPath = '/';
  String host = 'server';
  String shell = 'bash';
  String openedAt = '';

  _TerminalTabSession({
    required this.id,
    required this.title,
    this.outputLines = const <String>[],
    this.commandHistory = const <String>[],
  });
}

class _TerminalWorkspace {
  final List<_TerminalTabSession> tabs;
  String activeTabId;

  _TerminalWorkspace({
    required this.tabs,
    required this.activeTabId,
  });
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _commandFocusNode = FocusNode();

  final Map<String, _TerminalWorkspace> _workspaces = {};
  String? _activeServerId;

  @override
  void initState() {
    super.initState();
    _commandController.addListener(_cacheActiveTabDraft);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final provider = Provider.of<AppProvider>(context, listen: false);
      await _handleServerChanged(provider.selectedServer);
    });
  }

  @override
  void dispose() {
    _commandController.removeListener(_cacheActiveTabDraft);
    _commandController.dispose();
    _scrollController.dispose();
    _commandFocusNode.dispose();
    super.dispose();
  }

  _TerminalWorkspace? _activeWorkspace() {
    if (_activeServerId == null) {
      return null;
    }
    return _workspaces[_activeServerId!];
  }

  _TerminalTabSession? _activeTab() {
    final workspace = _activeWorkspace();
    if (workspace == null) {
      return null;
    }
    for (final tab in workspace.tabs) {
      if (tab.id == workspace.activeTabId) {
        return tab;
      }
    }
    return workspace.tabs.isEmpty ? null : workspace.tabs.first;
  }

  Future<void> _handleServerChanged(Server? server) async {
    _cacheActiveTabDraft();
    _activeServerId = server?.id;

    if (server == null) {
      _commandController.clear();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final existing = _workspaces[server.id];
    if (existing == null || existing.tabs.isEmpty) {
      final firstTab = _createTabModel(index: 1);
      final workspace = _TerminalWorkspace(
        tabs: [firstTab],
        activeTabId: firstTab.id,
      );
      _workspaces[server.id] = workspace;
      _applyActiveTabDraft();
      if (mounted) {
        setState(() {});
      }
      await _bootstrapTab(firstTab, server);
      return;
    }

    _applyActiveTabDraft();
    if (mounted) {
      setState(() {});
    }
    _scrollToBottom(jumpOnly: true);
  }

  _TerminalTabSession _createTabModel({required int index}) {
    return _TerminalTabSession(
      id: 'tab_${DateTime.now().microsecondsSinceEpoch}_$index',
      title: '终端 $index',
      outputLines: const <String>[],
      commandHistory: <String>[],
    );
  }

  Future<void> _bootstrapTab(_TerminalTabSession tab, Server server) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    tab.isBusy = true;
    tab.outputLines = <String>[
      '正在连接 ${server.name} (${server.ip})…',
      '',
    ];
    if (mounted) {
      setState(() {});
    }

    final ready = await provider.ensureTerminalConnection();
    if (!ready) {
      tab.isBusy = false;
      tab.outputLines = <String>[
        '无法连接到 ${server.name} (${server.ip})',
        '请先确认服务器已连接后再打开终端。',
        '',
      ];
      if (mounted) {
        setState(() {});
      }
      return;
    }

    try {
      final raw = await provider.executeSelectedCommand(
        _buildBootstrapCommand(),
      );
      final bootstrap = _parseBootstrapData(raw, server);
      tab.host = bootstrap.host;
      tab.currentPath = bootstrap.currentPath;
      tab.shell = bootstrap.shell;
      tab.openedAt = bootstrap.openedAt;
      tab.outputLines = _buildWelcomeLines(server, bootstrap);
    } catch (error) {
      tab.outputLines = <String>[
        '已连接到 ${server.name} (${server.ip})',
        '终端欢迎信息加载失败：${error.toString().replaceFirst('Exception: ', '')}',
        '',
      ];
    } finally {
      tab.isBusy = false;
      if (_activeTab()?.id == tab.id) {
        _applyActiveTabDraft();
      }
      if (mounted) {
        setState(() {});
      }
      _scrollToBottom(jumpOnly: true);
    }
  }

  List<String> _buildWelcomeLines(
    Server server,
    _TerminalBootstrapData bootstrap,
  ) {
    return <String>[
      'Last login: ${bootstrap.openedAt} via ShellGuard Desktop',
      'Connected to ${server.name} (${server.ip})',
      'Welcome to ${server.osDisplayLabel}${bootstrap.kernel.trim().isEmpty ? '' : ' · kernel ${bootstrap.kernel}'}',
      'User: ${server.username}   Host: ${bootstrap.host}   Shell: ${bootstrap.shell}',
      if (bootstrap.uptime.trim().isNotEmpty) 'Uptime: ${bootstrap.uptime}',
      'Working directory: ${bootstrap.currentPath}',
      '',
    ];
  }

  String _buildBootstrapCommand() {
    final script = '''
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$HOME/.local/share/uv/bin:\$PATH";
[ -f /etc/profile ] && . /etc/profile >/dev/null 2>&1;
[ -f "\$HOME/.profile" ] && . "\$HOME/.profile" >/dev/null 2>&1;
[ -f "\$HOME/.bash_profile" ] && . "\$HOME/.bash_profile" >/dev/null 2>&1;
[ -f "\$HOME/.bashrc" ] && . "\$HOME/.bashrc" >/dev/null 2>&1;
printf "__SG_HOST__=%s\n" "\$(hostname 2>/dev/null || echo unknown)";
printf "__SG_PWD__=%s\n" "\$PWD";
printf "__SG_SHELL__=%s\n" "\${SHELL:-bash}";
printf "__SG_TIME__=%s\n" "\$(date '+%a %b %d %H:%M:%S %Y' 2>/dev/null || date)";
printf "__SG_KERNEL__=%s\n" "\$(uname -r 2>/dev/null || echo '')";
printf "__SG_UPTIME__=%s\n" "\$(uptime -p 2>/dev/null || echo '')";
''';
    return 'bash -lc ${_shellQuote(script)}';
  }

  String _buildTerminalCommand(_TerminalTabSession tab, String command) {
    final script = '''
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$HOME/.local/share/uv/bin:\$PATH";
[ -f /etc/profile ] && . /etc/profile >/dev/null 2>&1;
[ -f "\$HOME/.profile" ] && . "\$HOME/.profile" >/dev/null 2>&1;
[ -f "\$HOME/.bash_profile" ] && . "\$HOME/.bash_profile" >/dev/null 2>&1;
[ -f "\$HOME/.bashrc" ] && . "\$HOME/.bashrc" >/dev/null 2>&1;
cd ${_shellQuote(tab.currentPath)} >/dev/null 2>&1 || cd "\$HOME" >/dev/null 2>&1 || true;
$command
status=\$?
printf "\n__SG_PWD__=%s\n" "\$PWD"
exit \$status
''';
    return 'bash -lc ${_shellQuote(script)}';
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  _TerminalBootstrapData _parseBootstrapData(String raw, Server server) {
    final markers = _extractMarkers(raw);
    return _TerminalBootstrapData(
      host: markers['__SG_HOST__']?.trim().isNotEmpty == true
          ? markers['__SG_HOST__']!.trim()
          : server.name,
      currentPath: markers['__SG_PWD__']?.trim().isNotEmpty == true
          ? markers['__SG_PWD__']!.trim()
          : '/',
      shell: markers['__SG_SHELL__']?.trim().isNotEmpty == true
          ? markers['__SG_SHELL__']!.trim()
          : 'bash',
      openedAt: markers['__SG_TIME__']?.trim().isNotEmpty == true
          ? markers['__SG_TIME__']!.trim()
          : DateTime.now().toString(),
      kernel: markers['__SG_KERNEL__']?.trim() ?? '',
      uptime: markers['__SG_UPTIME__']?.trim() ?? '',
    );
  }

  _TerminalCommandResult _parseTerminalCommandResult(
    String raw,
    _TerminalTabSession tab,
  ) {
    final markers = _extractMarkers(raw);
    final currentPath = markers['__SG_PWD__']?.trim().isNotEmpty == true
        ? markers['__SG_PWD__']!.trim()
        : tab.currentPath;
    final sanitizedLines = raw
        .split('\n')
        .where(
          (line) =>
              !line.startsWith('__SG_PWD__=') &&
              !line.startsWith('__SG_HOST__=') &&
              !line.startsWith('__SG_SHELL__=') &&
              !line.startsWith('__SG_TIME__=') &&
              !line.startsWith('__SG_KERNEL__=') &&
              !line.startsWith('__SG_UPTIME__='),
        )
        .toList();
    return _TerminalCommandResult(
      output: sanitizedLines.join('\n').trimRight(),
      currentPath: currentPath,
    );
  }

  Map<String, String> _extractMarkers(String raw) {
    final result = <String, String>{};
    for (final line in raw.split('\n')) {
      final index = line.indexOf('=');
      if (!line.startsWith('__SG_') || index <= 0) {
        continue;
      }
      result[line.substring(0, index)] = line.substring(index + 1);
    }
    return result;
  }

  String _buildPrompt(Server server, _TerminalTabSession tab) {
    final segment = _pathTail(tab.currentPath);
    final isRoot = server.username.trim() == 'root';
    return '[${server.username}@${tab.host} $segment]${isRoot ? '#' : '\$'}';
  }

  String _pathTail(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty || normalized == '/') {
      return '/';
    }
    final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? '/' : parts.last;
  }

  void _cacheActiveTabDraft() {
    final activeTab = _activeTab();
    if (activeTab == null) {
      return;
    }
    activeTab.draftCommand = _commandController.text;
  }

  void _applyActiveTabDraft() {
    final activeTab = _activeTab();
    final value = activeTab?.draftCommand ?? '';
    _commandController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _openNewTab() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final server = provider.selectedServer;
    if (server == null) {
      return;
    }
    final workspace = _activeWorkspace();
    if (workspace == null) {
      return;
    }
    final tab = _createTabModel(index: workspace.tabs.length + 1);
    workspace.tabs.add(tab);
    workspace.activeTabId = tab.id;
    _applyActiveTabDraft();
    if (mounted) {
      setState(() {});
    }
    await _bootstrapTab(tab, server);
  }

  void _switchTab(String tabId) {
    final workspace = _activeWorkspace();
    if (workspace == null || workspace.activeTabId == tabId) {
      return;
    }
    _cacheActiveTabDraft();
    workspace.activeTabId = tabId;
    _applyActiveTabDraft();
    setState(() {});
    _commandFocusNode.requestFocus();
    _scrollToBottom(jumpOnly: true);
  }

  void _closeTab(String tabId) {
    final workspace = _activeWorkspace();
    if (workspace == null || workspace.tabs.length <= 1) {
      return;
    }
    final index = workspace.tabs.indexWhere((tab) => tab.id == tabId);
    if (index == -1) {
      return;
    }
    workspace.tabs.removeAt(index);
    if (workspace.activeTabId == tabId) {
      final nextIndex = index == 0 ? 0 : index - 1;
      workspace.activeTabId = workspace.tabs[nextIndex].id;
      _applyActiveTabDraft();
    }
    setState(() {});
  }

  void _clearActiveTerminalOutput(Server? server) {
    final activeTab = _activeTab();
    if (activeTab == null || server == null) {
      return;
    }
    activeTab.outputLines = _buildWelcomeLines(
      server,
      _TerminalBootstrapData(
        host: activeTab.host,
        currentPath: activeTab.currentPath,
        shell: activeTab.shell,
        openedAt: activeTab.openedAt,
        kernel: server.kernelVersion ?? '',
        uptime: server.uptime ?? '',
      ),
    );
    activeTab.historyCursor = -1;
    activeTab.historyDraft = '';
    activeTab.commandHistory = <String>[];
    setState(() {});
    _scrollToBottom(jumpOnly: true);
  }

  Future<void> _executeCommand() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final server = provider.selectedServer;
    final activeTab = _activeTab();
    final command = _commandController.text.trim();
    if (server == null || activeTab == null || command.isEmpty || activeTab.isBusy) {
      return;
    }

    final ready = await provider.ensureTerminalConnection();
    if (!ready) {
      activeTab.outputLines.addAll(<String>[
        '${_buildPrompt(server, activeTab)} $command',
        '无法连接到服务器，请先建立连接。',
        '',
      ]);
      _commandController.clear();
      setState(() {});
      _scrollToBottom();
      return;
    }

    if (activeTab.historyCursor == -1) {
      activeTab.historyDraft = '';
    }
    if (activeTab.commandHistory.isEmpty || activeTab.commandHistory.first != command) {
      activeTab.commandHistory.insert(0, command);
    }
    activeTab.historyCursor = -1;
    activeTab.historyDraft = '';
    activeTab.isBusy = true;
    activeTab.outputLines.add('${_buildPrompt(server, activeTab)} $command');
    _commandController.clear();
    setState(() {});
    _scrollToBottom();

    try {
      final raw = await provider.executeSelectedCommand(
        _buildTerminalCommand(activeTab, command),
      );
      final result = _parseTerminalCommandResult(raw, activeTab);
      activeTab.currentPath = result.currentPath;
      if (result.output.isNotEmpty) {
        activeTab.outputLines.addAll(result.output.split('\n'));
      }
      await provider.saveOperationLog(
        command: command,
        result: result.output.isEmpty ? 'Command completed' : result.output,
      );
    } catch (error) {
      final parsed = _parseTerminalCommandResult(
        error.toString().replaceFirst('Exception: ', ''),
        activeTab,
      );
      activeTab.currentPath = parsed.currentPath;
      if (parsed.output.isNotEmpty) {
        activeTab.outputLines.addAll(parsed.output.split('\n'));
      } else {
        activeTab.outputLines.add('Command failed');
      }
      await provider.saveOperationLog(
        command: command,
        result: parsed.output.isEmpty ? error.toString() : parsed.output,
      );
    } finally {
      activeTab.outputLines.add('');
      activeTab.isBusy = false;
      if (mounted) {
        setState(() {});
      }
      _scrollToBottom();
    }
  }

  void _navigateHistory(int offset) {
    final activeTab = _activeTab();
    if (activeTab == null || activeTab.commandHistory.isEmpty) {
      return;
    }
    if (activeTab.historyCursor == -1) {
      activeTab.historyDraft = _commandController.text;
    }
    final nextCursor = activeTab.historyCursor + offset;
    if (nextCursor < 0) {
      activeTab.historyCursor = -1;
      _commandController.value = TextEditingValue(
        text: activeTab.historyDraft,
        selection: TextSelection.collapsed(offset: activeTab.historyDraft.length),
      );
      return;
    }
    if (nextCursor >= activeTab.commandHistory.length) {
      return;
    }
    activeTab.historyCursor = nextCursor;
    final value = activeTab.commandHistory[nextCursor];
    _commandController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _scrollToBottom({bool jumpOnly = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      if (jumpOnly) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    if (_activeServerId != provider.selectedServer?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        await _handleServerChanged(provider.selectedServer);
      });
    }

    final activeTab = _activeTab();
    final server = provider.selectedServer;

    return AdaptivePageLayout(
      backgroundColor: const Color(0xFF111315),
      estimatedReservedHeight: 184,
      minBodyHeight: 280,
      header: [
        _buildTabStrip(provider),
        const SizedBox(height: 12),
        _buildSessionBar(server, activeTab),
        const SizedBox(height: 12),
      ],
      body: _buildTerminalViewport(activeTab),
      footer: [
        const SizedBox(height: 12),
        _buildCommandBar(provider, server, activeTab),
      ],
    );
  }

  Widget _buildTabStrip(AppProvider provider) {
    final workspace = _activeWorkspace();
    final tabs = workspace?.tabs ?? const <_TerminalTabSession>[];
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF181B1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF242933)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              separatorBuilder: (_, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isActive = workspace?.activeTabId == tab.id;
                return _buildTabChip(tab, isActive, tabs.length > 1);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '新建终端',
            onPressed: provider.selectedServer == null ? null : _openNewTab,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 18),
            color: const Color(0xFF9CA3AF),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF101317),
              foregroundColor: const Color(0xFFD1D5DB),
              disabledForegroundColor: const Color(0xFF6B7280),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(
    _TerminalTabSession tab,
    bool isActive,
    bool canClose,
  ) {
    return Material(
      color: isActive ? const Color(0xFF0F1318) : const Color(0xFF1F242B),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _switchTab(tab.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF2DD4BF)
                  : const Color(0xFF2B313C),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tab.isBusy)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF2DD4BF),
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF2DD4BF)
                        : const Color(0xFF6B7280),
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 10),
              Text(
                tab.title,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFFE5FDF7)
                      : const Color(0xFFD1D5DB),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (canClose) ...[
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => _closeTab(tab.id),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: isActive
                          ? const Color(0xFFA7F3D0)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionBar(Server? server, _TerminalTabSession? tab) {
    if (server == null || tab == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF181B1F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF242933)),
        ),
        child: const Text(
          '请选择并连接服务器后再打开终端。',
          style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
        ),
      );
    }

    Widget chip(IconData icon, String text, Color accent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1318),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF181B1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF242933)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip(Icons.dns_outlined, server.name, const Color(0xFF2DD4BF)),
                chip(Icons.person_outline, server.username, const Color(0xFF60A5FA)),
                chip(Icons.folder_open_outlined, tab.currentPath, const Color(0xFFF59E0B)),
                chip(Icons.memory_outlined, server.osDisplayLabel, const Color(0xFFA78BFA)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: tab.isBusy ? null : () => _clearActiveTerminalOutput(server),
            style: AppButtonStyles.text(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ).copyWith(
              foregroundColor: const WidgetStatePropertyAll(Color(0xFF9CA3AF)),
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('清屏'),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalViewport(_TerminalTabSession? activeTab) {
    final lines = activeTab?.outputLines ?? const <String>[];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF20242C)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          final style = _lineStyle(line);
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              line,
              style: style,
              softWrap: true,
            ),
          );
        },
      ),
    );
  }

  TextStyle _lineStyle(String line) {
    Color color = const Color(0xFFE5E7EB);
    FontWeight weight = FontWeight.w500;
    if (line.startsWith('Last login:')) {
      color = const Color(0xFF93C5FD);
    } else if (line.startsWith('Connected to')) {
      color = const Color(0xFF2DD4BF);
    } else if (line.startsWith('Welcome to')) {
      color = const Color(0xFFFDE68A);
      weight = FontWeight.w600;
    } else if (line.startsWith('User:') || line.startsWith('Working directory:') || line.startsWith('Uptime:')) {
      color = const Color(0xFF9CA3AF);
    } else if (line.startsWith('[')) {
      color = const Color(0xFFFFFFFF);
      weight = FontWeight.w600;
    } else if (line.contains('无法连接') || line.contains('失败')) {
      color = const Color(0xFFFCA5A5);
    }
    return TextStyle(
      fontSize: 14,
      fontFamily: 'Monospace',
      color: color,
      fontWeight: weight,
      height: 1.35,
    );
  }

  Widget _buildCommandBar(
    AppProvider provider,
    Server? server,
    _TerminalTabSession? activeTab,
  ) {
    final enabled = server != null && activeTab != null && !activeTab.isBusy;
    final prompt = server == null || activeTab == null
        ? '\$'
        : _buildPrompt(server, activeTab);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181B1F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF242933)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            prompt,
            style: const TextStyle(
              fontSize: 14,
              fontFamily: 'Monospace',
              fontWeight: FontWeight.w700,
              color: Color(0xFF2DD4BF),
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
                enabled: enabled,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '输入命令后按 Enter 执行…',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                  border: InputBorder.none,
                ),
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'Monospace',
                  color: Color(0xFFF9FAFB),
                ),
                cursorColor: const Color(0xFF2DD4BF),
                onSubmitted: (_) => _executeCommand(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (activeTab?.isBusy == true)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF2DD4BF),
              ),
            )
          else
            ElevatedButton(
              onPressed: enabled ? _executeCommand : null,
              style: AppButtonStyles.primary(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ).copyWith(
                backgroundColor: const WidgetStatePropertyAll(Color(0xFF0F766E)),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
              ),
              child: const Text('执行命令'),
            ),
        ],
      ),
    );
  }
}
