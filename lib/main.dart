import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import './providers/app_provider.dart';
import './core/refresh_scope.dart';
import './widgets/sidebar.dart';
import './widgets/top_bar.dart';
import './screens/dashboard_screen.dart';
import './screens/asset_management_screen.dart';
import './screens/tool_installation_screen.dart';
import './screens/firewall_screen.dart';
import './screens/port_management_screen.dart';
import './screens/process_management_screen.dart';
import './screens/service_management_screen.dart';
import './screens/docker_screen.dart';
import './screens/monitoring_screen.dart';
import './screens/file_management_screen.dart';
import './screens/terminal_screen.dart';
import './screens/ai_assistant_screen.dart';
import './screens/settings_screen.dart';
import './widgets/app_button_styles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppProvider()..init())],
      child: MaterialApp(
        title: 'ShellGuard',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
          ),
          primaryColor: AppColors.primary,
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: const Color(0xFFf0f4f8),
          fontFamily: 'Roboto',
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: AppButtonStyles.primary(),
          ),
          textButtonTheme: TextButtonThemeData(style: AppButtonStyles.text()),
        ),
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const List<String> _screenOrder = [
    'dashboard',
    'assets',
    'ai_assistant',
    'tools',
    'firewall',
    'ports',
    'processes',
    'services',
    'docker',
    'monitoring',
    'files',
    'terminal',
    'settings',
  ];

  String _currentScreen = 'dashboard';
  final Set<String> _visitedScreens = {'dashboard'};
  final GlobalKey<DashboardScreenState> _dashboardKey = GlobalKey();
  final GlobalKey<FileManagementScreenState> _filesKey = GlobalKey();
  final GlobalKey<PortManagementScreenState> _portsKey = GlobalKey();
  final GlobalKey<ProcessManagementScreenState> _processesKey = GlobalKey();
  final GlobalKey<ServiceManagementScreenState> _servicesKey = GlobalKey();
  final GlobalKey<DockerScreenState> _dockerKey = GlobalKey();
  final GlobalKey<FirewallScreenState> _firewallKey = GlobalKey();
  final GlobalKey<MonitoringScreenState> _monitoringKey = GlobalKey();

  void _navigateTo(String screen) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    provider.setCurrentScreen(screen);
    setState(() {
      _currentScreen = screen;
      _visitedScreens.add(screen);
    });
    unawaited(_handleScreenEnter(provider, screen));
  }

  Future<void> _handleScreenEnter(AppProvider provider, String screen) async {
    switch (screen) {
      case 'dashboard':
      case 'monitoring':
        await provider.onPageEnter(RefreshScope.dashboard);
        break;
      case 'firewall':
        await provider.onPageEnter(RefreshScope.firewall);
        break;
      case 'ports':
        await provider.onPageEnter(RefreshScope.ports);
        break;
      case 'processes':
        await provider.onPageEnter(RefreshScope.processes);
        break;
      case 'services':
        await provider.onPageEnter(RefreshScope.services);
        break;
      case 'docker':
        await provider.onPageEnter(RefreshScope.docker);
        break;
      case 'files':
        await provider.onPageEnter(
          RefreshScope.files,
          filePath: _filesKey.currentState?.currentPathForRefresh,
        );
        break;
      default:
        break;
    }
  }

  void _handleRefresh() {
    switch (_currentScreen) {
      case 'dashboard':
        _dashboardKey.currentState?.refresh();
        break;
      case 'files':
        _filesKey.currentState?.refresh();
        break;
      case 'ports':
        _portsKey.currentState?.refresh();
        break;
      case 'processes':
        _processesKey.currentState?.refresh();
        break;
      case 'services':
        _servicesKey.currentState?.refresh();
        break;
      case 'docker':
        _dockerKey.currentState?.refresh();
        break;
      case 'firewall':
        _firewallKey.currentState?.refresh();
        break;
      case 'monitoring':
        _monitoringKey.currentState?.refresh();
        break;
    }
  }

  Future<void> _handleConnect() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final connectSelectionId = provider.selectedServer?.id;
    final success = await provider.connectToServer();
    if (!mounted) {
      return;
    }
    final selectionChanged = provider.selectedServer?.id != connectSelectionId;
    if (!selectionChanged && !success && provider.errorMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    }
    setState(() {});
  }

  Widget _buildScreen(String screen) {
    switch (screen) {
      case 'dashboard':
        return DashboardScreen(key: _dashboardKey, onNavigate: _navigateTo);
      case 'assets':
        return const AssetManagementScreen();
      case 'ai_assistant':
        return const AiAssistantScreen();
      case 'tools':
        return const ToolInstallationScreen();
      case 'firewall':
        return FirewallScreen(key: _firewallKey);
      case 'ports':
        return PortManagementScreen(key: _portsKey);
      case 'processes':
        return ProcessManagementScreen(key: _processesKey);
      case 'services':
        return ServiceManagementScreen(key: _servicesKey);
      case 'docker':
        return DockerScreen(key: _dockerKey);
      case 'monitoring':
        return MonitoringScreen(key: _monitoringKey);
      case 'files':
        return FileManagementScreen(key: _filesKey);
      case 'terminal':
        return const TerminalScreen();
      case 'settings':
        return const SettingsScreen();
      default:
        return DashboardScreen(key: _dashboardKey, onNavigate: _navigateTo);
    }
  }

  String _getScreenTitle() {
    switch (_currentScreen) {
      case 'dashboard':
        return '仪表盘';
      case 'assets':
        return '服务器资产管理';
      case 'ai_assistant':
        return 'AI助力';
      case 'tools':
        return '系统工具安装';
      case 'firewall':
        return '防火墙管理';
      case 'ports':
        return '端口管理';
      case 'processes':
        return '进程管理';
      case 'services':
        return '服务管理';
      case 'docker':
        return 'Docker管理';
      case 'monitoring':
        return '资源监控';
      case 'files':
        return '文件管理';
      case 'terminal':
        return 'Web终端';
      case 'settings':
        return '系统设置';
      default:
        return 'ShellGuard';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Sidebar(onNavigate: _navigateTo, currentScreen: _currentScreen),
          Expanded(
            child: Column(
              children: [
                TopBar(
                  title: _getScreenTitle(),
                  onRefresh: _handleRefresh,
                  onConnect: _handleConnect,
                ),
                Expanded(
                  child: IndexedStack(
                    index: _screenOrder.indexOf(_currentScreen),
                    children: _screenOrder.map((screen) {
                      if (!_visitedScreens.contains(screen)) {
                        return const SizedBox.shrink();
                      }
                      return _buildScreen(screen);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
