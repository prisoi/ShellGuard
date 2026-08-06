import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../models/server.dart';
import '../models/terminal_session_models.dart';
import '../providers/app_provider.dart';
import '../widgets/adaptive_page_layout.dart';
import '../widgets/app_button_styles.dart';

class _TerminalTab {
  final String id;
  String title;
  Terminal terminal;
  TerminalController controller;
  FocusNode focusNode;
  TerminalSessionHandle? session;
  StreamSubscription<String>? outputSubscription;
  bool isConnecting = false;
  bool isClosed = false;
  bool hasStarted = false;
  String status;

  _TerminalTab({
    required this.id,
    required this.title,
    required this.terminal,
    required this.controller,
    required this.focusNode,
    this.status = '准备连接',
  });
}

class _TerminalWorkspace {
  final String serverId;
  final List<_TerminalTab> tabs;
  String activeTabId;

  _TerminalWorkspace({
    required this.serverId,
    required this.tabs,
    required this.activeTabId,
  });
}

enum _TerminalContextAction {
  copy,
  paste,
  selectAll,
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final Map<String, _TerminalWorkspace> _workspaces = {};
  String? _activeServerId;

  bool get _useHardwareKeyboardOnly {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  static const TerminalTheme _terminalTheme = TerminalTheme(
    cursor: Color(0xFF2DD4BF),
    selection: Color(0x5534D399),
    foreground: Color(0xFFE5E7EB),
    background: Color(0xFF0A0D12),
    black: Color(0xFF111827),
    red: Color(0xFFF87171),
    green: Color(0xFF34D399),
    yellow: Color(0xFFFBBF24),
    blue: Color(0xFF60A5FA),
    magenta: Color(0xFFC084FC),
    cyan: Color(0xFF22D3EE),
    white: Color(0xFFE5E7EB),
    brightBlack: Color(0xFF6B7280),
    brightRed: Color(0xFFFCA5A5),
    brightGreen: Color(0xFF6EE7B7),
    brightYellow: Color(0xFFFDE68A),
    brightBlue: Color(0xFF93C5FD),
    brightMagenta: Color(0xFFD8B4FE),
    brightCyan: Color(0xFF67E8F9),
    brightWhite: Color(0xFFF9FAFB),
    searchHitBackground: Color(0xFF3F6212),
    searchHitBackgroundCurrent: Color(0xFF65A30D),
    searchHitForeground: Color(0xFFFFFFFF),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final provider = Provider.of<AppProvider>(context, listen: false);
      await _handleServerChanged(provider);
    });
  }

  @override
  void dispose() {
    final futures = <Future<void>>[];
    for (final workspace in _workspaces.values) {
      futures.add(_disposeWorkspace(workspace));
    }
    unawaited(Future.wait(futures));
    super.dispose();
  }

  _TerminalWorkspace? _activeWorkspace() {
    if (_activeServerId == null) {
      return null;
    }
    return _workspaces[_activeServerId!];
  }

  _TerminalTab? _activeTab() {
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

  Future<void> _handleServerChanged(AppProvider provider) async {
    final selected = provider.selectedServer;
    if (selected == null) {
      _activeServerId = null;
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _activeServerId = selected.id;
    var workspace = _workspaces[selected.id];
    if (workspace == null) {
      workspace = _TerminalWorkspace(
        serverId: selected.id,
        tabs: <_TerminalTab>[],
        activeTabId: '',
      );
      _workspaces[selected.id] = workspace;
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (mounted) {
      setState(() {});
    }
    _focusActiveTab();
  }

  _TerminalTab _createTab({required int index}) {
    late final _TerminalTab tab;
    final terminal = Terminal(
      maxLines: 10000,
    );
    final controller = TerminalController();
    final focusNode = FocusNode(debugLabel: 'terminal_tab_$index');

    tab = _TerminalTab(
      id: 'terminal_${DateTime.now().microsecondsSinceEpoch}_$index',
      title: index == 1 ? '终端' : '终端 $index',
      terminal: terminal,
      controller: controller,
      focusNode: focusNode,
      status: '准备连接',
    );

    terminal.onOutput = (data) {
      tab.session?.write(data);
    };
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      tab.session?.resize(width, height, pixelWidth, pixelHeight);
    };

    return tab;
  }

  Future<void> _startShellForTab(
    _TerminalTab tab,
    Server server,
    AppProvider provider,
  ) async {
    tab.hasStarted = true;
    tab.isConnecting = true;
    tab.isClosed = false;
    tab.status = '正在连接 ${server.name}';
    tab.terminal.write(_buildWelcomeBanner(server));
    if (mounted) {
      setState(() {});
    }

    try {
      final handle = await provider.openSelectedTerminalSession();
      tab.session = handle;
      tab.status = '已连接到 ${server.name}';
      tab.outputSubscription = handle.stream.listen((chunk) {
        tab.terminal.write(chunk);
      });
      unawaited(
        handle.done.then((result) {
          tab.isClosed = true;
          tab.isConnecting = false;
          tab.status = result.disconnected
              ? '终端已断开'
              : '终端已结束（exit ${result.exitCode ?? '-'}）';
          tab.terminal.write(
            '\r\n[ShellGuard] ${tab.status}，可新开终端继续操作。\r\n',
          );
          if (mounted) {
            setState(() {});
          }
        }),
      );
      _focusTab(tab);
    } catch (error) {
      tab.isClosed = true;
      tab.status = error.toString().replaceFirst('Exception: ', '');
      tab.terminal.write('\r\n[ShellGuard] ${tab.status}\r\n');
    } finally {
      tab.isConnecting = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  String _buildWelcomeBanner(Server server) {
    final time = DateTime.now();
    final minute = time.minute.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return ''
        'Last login: ${time.year}-$month-$day $hour:$minute via ShellGuard Desktop\r\n'
        'Connecting to ${server.name} (${server.ip.isEmpty ? 'shared-terminal' : server.ip})\r\n'
        'OS: ${server.osDisplayLabel}\r\n'
        'User: ${server.username.isEmpty ? 'shared-session' : server.username}\r\n'
        '\r\n';
  }

  Future<void> _openNewTab() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final server = provider.selectedServer;
    final workspace = _activeWorkspace();
    if (server == null || workspace == null) {
      return;
    }

    final tab = _createTab(index: workspace.tabs.length + 1);
    workspace.tabs.add(tab);
    workspace.activeTabId = tab.id;
    if (mounted) {
      setState(() {});
    }
    await _startShellForTab(tab, server, provider);
  }

  void _switchTab(String tabId) {
    final workspace = _activeWorkspace();
    if (workspace == null || workspace.activeTabId == tabId) {
      return;
    }
    workspace.activeTabId = tabId;
    if (mounted) {
      setState(() {});
    }
    _focusActiveTab();
  }

  Future<void> _closeTab(String tabId) async {
    final workspace = _activeWorkspace();
    if (workspace == null) {
      return;
    }
    final index = workspace.tabs.indexWhere((tab) => tab.id == tabId);
    if (index == -1) {
      return;
    }
    final tab = workspace.tabs.removeAt(index);
    await _disposeTab(tab);
    if (workspace.tabs.isEmpty) {
      workspace.activeTabId = '';
    } else if (workspace.activeTabId == tabId) {
      final nextIndex = index == 0 ? 0 : index - 1;
      workspace.activeTabId = workspace.tabs[nextIndex].id;
    }
    if (mounted) {
      setState(() {});
    }
    _focusActiveTab();
  }

  Future<void> _sendClear() async {
    final tab = _activeTab();
    if (tab?.session == null || tab!.isClosed || !tab.hasStarted) {
      return;
    }
    tab.session!.write('clear\r');
    _focusTab(tab);
  }

  Future<void> _sendInterrupt() async {
    final tab = _activeTab();
    if (tab?.session == null || tab!.isClosed || !tab.hasStarted) {
      return;
    }
    tab.session!.write('\u0003');
    _focusTab(tab);
  }

  Future<void> _copyOrPaste(_TerminalTab tab) async {
    final selection = tab.controller.selection;
    if (selection != null) {
      final text = tab.terminal.buffer.getText(selection);
      tab.controller.clearSelection();
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    tab.terminal.paste(text);
    _focusTab(tab);
  }

  Future<void> _copySelection(_TerminalTab tab) async {
    final selection = tab.controller.selection;
    if (selection == null) {
      return;
    }
    final text = tab.terminal.buffer.getText(selection);
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    tab.controller.clearSelection();
    _focusTab(tab);
  }

  Future<void> _pasteClipboard(_TerminalTab tab) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    tab.terminal.paste(text);
    _focusTab(tab);
  }

  void _selectAllTerminal(_TerminalTab tab) {
    final startLine = (tab.terminal.buffer.height - tab.terminal.viewHeight)
        .clamp(0, tab.terminal.buffer.height - 1);
    final endLine = (tab.terminal.buffer.height - 1).clamp(0, tab.terminal.buffer.height - 1);
    tab.controller.setSelection(
      tab.terminal.buffer.createAnchor(0, startLine),
      tab.terminal.buffer.createAnchor(tab.terminal.viewWidth, endLine),
      mode: SelectionMode.line,
    );
    _focusTab(tab);
  }

  Future<void> _showTerminalContextMenu(
    _TerminalTab tab,
    TapDownDetails details,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) {
      await _copyOrPaste(tab);
      return;
    }

    final action = await showMenu<_TerminalContextAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          details.globalPosition,
          details.globalPosition,
        ),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF111827),
      shadowColor: const Color(0x55000000),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF263040)),
      ),
      items: [
        PopupMenuItem(
          value: _TerminalContextAction.copy,
          child: _buildTerminalContextMenuItem(
            icon: Icons.copy_all_outlined,
            label: '复制',
          ),
        ),
        PopupMenuItem(
          value: _TerminalContextAction.paste,
          child: _buildTerminalContextMenuItem(
            icon: Icons.content_paste_go_outlined,
            label: '粘贴',
          ),
        ),
        PopupMenuItem(
          value: _TerminalContextAction.selectAll,
          child: _buildTerminalContextMenuItem(
            icon: Icons.select_all_outlined,
            label: '全选',
          ),
        ),
      ],
    );

    switch (action) {
      case _TerminalContextAction.copy:
        await _copySelection(tab);
        break;
      case _TerminalContextAction.paste:
        await _pasteClipboard(tab);
        break;
      case _TerminalContextAction.selectAll:
        _selectAllTerminal(tab);
        break;
      case null:
        break;
    }
  }

  Widget _buildTerminalContextMenuItem({
    required IconData icon,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: const Color(0xFFE5E7EB),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF8FAFC),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _focusActiveTab() {
    final tab = _activeTab();
    if (tab == null) {
      return;
    }
    _focusTab(tab);
  }

  void _focusTab(_TerminalTab tab) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      tab.focusNode.requestFocus();
    });
  }

  Future<void> _disposeWorkspace(_TerminalWorkspace workspace) async {
    for (final tab in workspace.tabs) {
      await _disposeTab(tab);
    }
  }

  Future<void> _disposeTab(_TerminalTab tab) async {
    await tab.outputSubscription?.cancel();
    await tab.session?.close();
    tab.focusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    if (_activeServerId != provider.selectedServer?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        await _handleServerChanged(provider);
      });
    }

    final server = provider.selectedServer;
    final activeTab = _activeTab();

    return AdaptivePageLayout(
      backgroundColor: const Color(0xFF0D1117),
      estimatedReservedHeight: 156,
      minBodyHeight: 320,
      header: [
        _buildTabStrip(provider),
        const SizedBox(height: 12),
        _buildSessionToolbar(server, activeTab),
        const SizedBox(height: 12),
      ],
      body: _buildTerminalBody(activeTab),
    );
  }

  Widget _buildTabStrip(AppProvider provider) {
    final workspace = _activeWorkspace();
    final tabs = workspace?.tabs ?? const <_TerminalTab>[];
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF222B36)),
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
                return _buildTabChip(tab, isActive, true);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '新建终端',
            onPressed: provider.selectedServer == null ? null : _openNewTab,
            icon: const Icon(Icons.add, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF0F141B),
              foregroundColor: const Color(0xFFE5E7EB),
              disabledBackgroundColor: const Color(0xFF111827),
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

  Widget _buildTabChip(_TerminalTab tab, bool isActive, bool canClose) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _switchTab(tab.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0B0F15) : const Color(0xFF1B2330),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF2DD4BF)
                  : const Color(0xFF2A3340),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: tab.isConnecting
                      ? const Color(0xFFFBBF24)
                      : tab.isClosed
                          ? const Color(0xFF6B7280)
                          : const Color(0xFF34D399),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                tab.title,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFFD1D5DB),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (canClose) ...[
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => unawaited(_closeTab(tab.id)),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFF9CA3AF),
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

  Widget _buildSessionToolbar(Server? server, _TerminalTab? activeTab) {
    if (server == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF222B36)),
        ),
        child: const Text(
          '请选择并连接服务器后再打开 Web 终端。',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
      );
    }

    final userLabel = server.username.isEmpty ? '共享会话' : server.username;

    Widget pill(IconData icon, String text, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0F15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    if (activeTab == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF222B36)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  pill(Icons.dns_outlined, server.name, const Color(0xFF2DD4BF)),
                  pill(Icons.person_outline, userLabel, const Color(0xFF60A5FA)),
                  pill(Icons.memory_outlined, server.osDisplayLabel, const Color(0xFFC084FC)),
                  pill(Icons.pause_circle_outline, '尚未建立终端连接', const Color(0xFF94A3B8)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _openNewTab,
              style: AppButtonStyles.primary(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建并连接'),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF222B36)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                pill(Icons.dns_outlined, server.name, const Color(0xFF2DD4BF)),
                pill(Icons.person_outline, userLabel, const Color(0xFF60A5FA)),
                pill(Icons.memory_outlined, server.osDisplayLabel, const Color(0xFFC084FC)),
                pill(
                  activeTab.isConnecting
                      ? Icons.sync
                      : activeTab.isClosed
                          ? Icons.link_off
                          : Icons.terminal,
                  activeTab.status,
                  activeTab.isConnecting
                      ? const Color(0xFFFBBF24)
                      : activeTab.isClosed
                          ? const Color(0xFFF87171)
                          : const Color(0xFF34D399),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: activeTab.isClosed ? null : () => _copySelection(activeTab),
                style: AppButtonStyles.text(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ).copyWith(
                  foregroundColor: const WidgetStatePropertyAll(
                    Color(0xFFBFDBFE),
                  ),
                ),
                icon: const Icon(Icons.copy_all_outlined, size: 16),
                label: const Text('复制'),
              ),
              TextButton.icon(
                onPressed: activeTab.isClosed ? null : () => _pasteClipboard(activeTab),
                style: AppButtonStyles.text(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ).copyWith(
                  foregroundColor: const WidgetStatePropertyAll(
                    Color(0xFFA7F3D0),
                  ),
                ),
                icon: const Icon(Icons.content_paste_go_outlined, size: 16),
                label: const Text('粘贴'),
              ),
              TextButton.icon(
                onPressed: activeTab.isClosed ? null : _sendInterrupt,
                style: AppButtonStyles.text(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ).copyWith(
                  foregroundColor: const WidgetStatePropertyAll(
                    Color(0xFFFCA5A5),
                  ),
                ),
                icon: const Icon(Icons.block, size: 16),
                label: const Text('发送中断'),
              ),
              TextButton.icon(
                onPressed: activeTab.isClosed ? null : _sendClear,
                style: AppButtonStyles.text(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ).copyWith(
                  foregroundColor: const WidgetStatePropertyAll(
                    Color(0xFF9CA3AF),
                  ),
                ),
                icon: const Icon(Icons.layers_clear_outlined, size: 16),
                label: const Text('清屏'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalBody(_TerminalTab? activeTab) {
    if (activeTab == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0D12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF202833)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      color: Color(0xFF111827),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.terminal,
                      color: Color(0xFF2DD4BF),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '尚未建立终端连接',
                    style: TextStyle(
                      color: Color(0xFFF8FAFC),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '为避免切换服务器时自动建立 SSH 会话造成网络拥堵，ShellGuard 现在只有在你点击右上角 + 后才会创建第一个终端连接。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _openNewTab,
                    style: AppButtonStyles.primary(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新建终端并连接'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF202833)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TerminalView(
                activeTab.terminal,
                controller: activeTab.controller,
                focusNode: activeTab.focusNode,
                autofocus: true,
                hardwareKeyboardOnly: _useHardwareKeyboardOnly,
                theme: _terminalTheme,
                backgroundOpacity: 1,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                textStyle: const TerminalStyle(
                  fontSize: 14,
                  height: 1.28,
                ),
                alwaysShowCursor: true,
                onSecondaryTapDown: (details, offset) {
                  unawaited(_showTerminalContextMenu(activeTab, details));
                },
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xCC111827),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF263040)),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  '右键菜单 / Ctrl+Shift+C 复制 / Ctrl+V 粘贴',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
