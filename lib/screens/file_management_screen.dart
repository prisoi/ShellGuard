import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/refresh_scope.dart';
import '../core/ssh_manager.dart';
import '../models/query_options.dart';
import '../models/server.dart';
import '../providers/app_provider.dart';
import '../services/file_transfer_service.dart';
import '../widgets/app_button_styles.dart';
import '../widgets/sort_header_cell.dart';

class FileManagementScreen extends StatefulWidget {
  const FileManagementScreen({super.key});

  @override
  State<FileManagementScreen> createState() => FileManagementScreenState();
}

class FileManagementScreenState extends State<FileManagementScreen> {
  final FileTransferService _fileTransferService = const FileTransferService();

  List<FileInfo> _files = [];
  String _currentPath = '/';
  String _lastValidPath = '/';
  bool _isLoading = false;
  String? _lastServerId;
  String? _lastUpdatedAt;
  String? _pendingPath;
  String? _pathErrorMessage;
  FileTransferProgress? _transferProgress;
  late final TextEditingController _pathController;
  String _searchText = '';
  String _sortBy = 'name';
  bool _sortAscending = true;
  String? _defaultDownloadDirectory;
  DateTime? _lastTransferUiUpdateAt;
  TransferCancellationToken? _activeTransferToken;

  bool get _hasActiveTransfer =>
      _transferProgress != null && !_transferProgress!.isFinished;
  String get currentPathForRefresh => _currentPath;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: _currentPath);
    _initDefaultDownloadDirectory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AppProvider>(context, listen: false);
      _applyCache(provider);
      _loadInitialPath(provider);
    });
  }

  @override
  void dispose() {
    _activeTransferToken?.cancel();
    _pathController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<AppProvider>(context);
    final serverId = provider.selectedServer?.id;
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.files.key];
    if (_lastServerId != serverId) {
      _activeTransferToken?.cancel();
      _lastServerId = serverId;
      _lastUpdatedAt = null;
      _currentPath = provider.currentCache?.currentPath ?? '/';
      _lastValidPath = _currentPath;
      _transferProgress = null;
      _activeTransferToken = null;
      _applyCache(provider);
      _loadInitialPath(provider);
    } else if (updatedAt != null && updatedAt != _lastUpdatedAt) {
      _applyCache(provider);
    }
  }

  void _applyCache(AppProvider provider) {
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.files.key];
    setState(() {
      _currentPath = provider.currentCache?.currentPath ?? _currentPath;
      _lastValidPath = _currentPath;
      _lastUpdatedAt = updatedAt;
      _pendingPath = null;
      _pathErrorMessage = null;
    });
    _pathController.text = _currentPath;
    _reloadFiles();
  }

  Future<void> _initDefaultDownloadDirectory() async {
    final directoryPath = await _resolveDefaultDownloadDirectory();
    if (!mounted) {
      return;
    }
    setState(() => _defaultDownloadDirectory = directoryPath);
  }

  Future<void> _reloadFiles() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final serverId = provider.selectedServer?.id;
    if (serverId == null) {
      if (!mounted) return;
      setState(() => _files = []);
      return;
    }
    final items = await provider.storageService.queryFiles(
      serverId: serverId,
      options: QueryOptions(
        keyword: _searchText,
        sortBy: _sortBy,
        direction: _sortAscending
            ? SortDirection.ascending
            : SortDirection.descending,
      ),
    );
    if (!mounted) return;
    setState(() => _files = items);
  }

  void _toggleSort(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = sortBy != 'size';
      }
    });
    _reloadFiles();
  }

  Future<void> _loadInitialPath(AppProvider provider) async {
    if (provider.selectedServer == null) {
      return;
    }
    final targetPath = provider.currentCache?.currentPath;
    await _navigateTo(
      targetPath == null || targetPath.trim().isEmpty ? null : targetPath,
      useLoginDirectoryWhenEmpty: true,
      allowFallback: true,
      showErrorOnMissing: false,
    );
  }

  Future<bool> _ensureFileSession(AppProvider provider) async {
    if (provider.selectedServer == null) {
      return false;
    }
    final success = await provider.ensureTerminalConnection();
    if (!success && mounted) {
      final message = provider.errorMessage.isEmpty
          ? '连接失败'
          : provider.errorMessage;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    return success;
  }

  FileTransferBackend _currentTransferBackend(AppProvider provider) {
    if (provider.isSharedSelection) {
      return ShareFileTransferBackend(
        client: provider.currentShareClient!,
        serverId: provider.selectedSharedServer!.remoteServerId,
      );
    }
    return SshFileTransferBackend(provider.sshManager);
  }

  void refresh() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;
    setState(() => _isLoading = true);
    Future(() async {
      await provider.requestRefreshNow(
        RefreshScope.files,
        reason: 'files-refresh',
        filePath: _currentPath,
      );
      if (!mounted) return;
      _applyCache(provider);
      setState(() => _isLoading = false);
    });
  }

  Future<void> _navigateTo(
    String? path, {
    bool useLoginDirectoryWhenEmpty = false,
    bool allowFallback = false,
    bool showErrorOnMissing = true,
  }) async {
    final requestedPath =
        (path == null || path.trim().isEmpty) && useLoginDirectoryWhenEmpty
        ? null
        : _normalizePath(path ?? _currentPath);
    final displayPath = requestedPath ?? _currentPath;
    if (_isLoading || _pendingPath == displayPath) {
      return;
    }
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) {
      return;
    }
    setState(() {
      _pendingPath = displayPath;
      _isLoading = true;
      _pathErrorMessage = null;
    });
    try {
      final ready = await _ensureFileSession(provider);
      if (!ready) {
        return;
      }
      final resolution = await provider.resolveSelectedDirectory(
        requestedPath,
        fallbackToParent: allowFallback,
      );

      if (!resolution.exists) {
        if (!mounted) {
          return;
        }
        setState(() {
          _currentPath = _lastValidPath;
          _pathController.text = _lastValidPath;
          _pathErrorMessage = '路径不存在: ${resolution.requestedPath}';
        });
        if (showErrorOnMissing) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('路径不存在，已回到 $_lastValidPath')));
        }
        await provider.requestRefreshNow(
          RefreshScope.files,
          reason: 'files-recover-invalid-path',
          filePath: _lastValidPath,
        );
        if (!mounted) {
          return;
        }
        _applyCache(provider);
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _currentPath = resolution.resolvedPath;
        _pathController.text = resolution.resolvedPath;
      });
      if (resolution.resolvedPath != resolution.requestedPath &&
          showErrorOnMissing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('目标路径不存在，已切换到 ${resolution.resolvedPath}')),
        );
      }
      await provider.requestRefreshNow(
        RefreshScope.files,
        reason: 'files-navigate',
        filePath: resolution.resolvedPath,
      );
      if (!mounted) {
        return;
      }
      _applyCache(provider);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _pendingPath = null;
        });
      }
    }
  }

  void _goBack() {
    if (_currentPath != '/') {
      final parts = _currentPath.split('/')..removeLast();
      final targetPath = parts.join('/') == '' ? '/' : parts.join('/');
      _navigateTo(targetPath, allowFallback: false);
    }
  }

  Future<void> _submitPath() async {
    await _navigateTo(
      _pathController.text,
      allowFallback: false,
      showErrorOnMissing: true,
    );
  }

  Future<void> _createDirectory() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;

    final name = await _showTextPrompt(
      title: '创建文件夹',
      hintText: '文件夹名称',
      submitLabel: '创建',
    );

    if (name != null && name.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final ready = await _ensureFileSession(provider);
        if (!ready) {
          return;
        }
        await provider.createDirectorySelected(_buildPath(name));
        await provider.requestRefreshNow(
          RefreshScope.files,
          reason: 'files-create-directory',
          filePath: _currentPath,
        );
        if (!mounted) return;
        _applyCache(provider);
      } catch (error) {
        _showSnackBar(_friendlyError(error));
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _createFile() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;

    final name = await _showTextPrompt(
      title: '新建文件',
      hintText: '文件名称，例如 config.env',
      submitLabel: '创建',
    );

    if (name != null && name.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final ready = await _ensureFileSession(provider);
        if (!ready) {
          return;
        }
        await provider.writeFileSelected(_buildPath(name), '');
        await provider.requestRefreshNow(
          RefreshScope.files,
          reason: 'files-create-file',
          filePath: _currentPath,
        );
        if (!mounted) return;
        _applyCache(provider);
      } catch (error) {
        _showSnackBar(_friendlyError(error));
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteFile(FileInfo file) async {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final provider = Provider.of<AppProvider>(dialogContext, listen: false);
        final navigator = Navigator.of(dialogContext);
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text('确定要删除 ${file.name} 吗？'),
          actions: [
            TextButton(
              onPressed: navigator.pop,
              style: AppButtonStyles.text(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                setState(() => _isLoading = true);
                try {
                  final ready = await _ensureFileSession(provider);
                  if (!ready) {
                    return;
                  }
                  await provider.deleteFileSelected(file.path);
                  await provider.requestRefreshNow(
                    RefreshScope.files,
                    reason: 'files-delete',
                    filePath: _currentPath,
                  );
                  if (!mounted) {
                    return;
                  }
                  _applyCache(provider);
                } catch (error) {
                  _showSnackBar(_friendlyError(error));
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                }
                if (navigator.mounted) {
                  navigator.pop();
                }
              },
              style: AppButtonStyles.textDanger(),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _renameFile(FileInfo file) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;

    final newName = await _showTextPrompt(
      title: '重命名',
      hintText: '新的名称',
      submitLabel: '保存',
      initialValue: file.name,
    );

    if (newName == null ||
        newName.trim().isEmpty ||
        newName.trim() == file.name) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final ready = await _ensureFileSession(provider);
      if (!ready) {
        return;
      }
      await provider.renameFileSelected(
        file.path,
        _buildPath(newName.trim()),
      );
      await provider.requestRefreshNow(
        RefreshScope.files,
        reason: 'files-rename',
        filePath: _currentPath,
      );
      if (!mounted) return;
      _applyCache(provider);
    } catch (error) {
      _showSnackBar(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _changePermissions(FileInfo file) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;

    final permission = await _showTextPrompt(
      title: '修改权限',
      hintText: '例如 644 / 755',
      submitLabel: '应用',
      initialValue: file.permissions.length >= 4
          ? _permissionToOctal(file.permissions)
          : '',
    );

    if (permission == null || permission.trim().isEmpty) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final ready = await _ensureFileSession(provider);
      if (!ready) {
        return;
      }
      await provider.executeSelectedCommand(
        'chmod ${permission.trim()} "${file.path}"',
      );
      await provider.requestRefreshNow(
        RefreshScope.files,
        reason: 'files-chmod',
        filePath: _currentPath,
      );
      if (!mounted) return;
      _applyCache(provider);
    } catch (error) {
      _showSnackBar(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadFile() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;
    final ready = await _ensureFileSession(provider);
    if (!ready) {
      return;
    }

    final localFilePath = await _pickLocalFilePath();
    if (localFilePath == null || localFilePath.trim().isEmpty) {
      return;
    }

    final remoteFilePath = _buildPath(p.basename(localFilePath));
    final canContinue = await _prepareRemoteDestination(
      remoteFilePath,
      label: p.basename(localFilePath),
    );
    if (!canContinue) {
      return;
    }

    final backend = _currentTransferBackend(provider);
    final cancelToken = TransferCancellationToken();
    await _runTransfer(
      cancelToken: cancelToken,
      operation: () => _fileTransferService.uploadFile(
        backend: backend,
        localFilePath: localFilePath,
        remoteFilePath: remoteFilePath,
        cancelToken: cancelToken,
        onProgress: _updateTransferProgress,
      ),
      successMessage: '文件已上传到 $remoteFilePath',
      refreshAfter: true,
    );
  }

  Future<void> _uploadDirectory() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;
    final ready = await _ensureFileSession(provider);
    if (!ready) {
      return;
    }

    final localDirectoryPath = await _pickLocalDirectoryPath();
    if (localDirectoryPath == null || localDirectoryPath.trim().isEmpty) {
      return;
    }

    final remoteDirectoryPath = _buildPath(p.basename(localDirectoryPath));
    final canContinue = await _prepareRemoteDestination(
      remoteDirectoryPath,
      label: p.basename(localDirectoryPath),
    );
    if (!canContinue) {
      return;
    }

    final backend = _currentTransferBackend(provider);
    final cancelToken = TransferCancellationToken();
    await _runTransfer(
      cancelToken: cancelToken,
      operation: () => _fileTransferService.uploadDirectory(
        backend: backend,
        localDirectoryPath: localDirectoryPath,
        remoteDirectoryPath: remoteDirectoryPath,
        cancelToken: cancelToken,
        onProgress: _updateTransferProgress,
      ),
      successMessage: '目录已上传到 $remoteDirectoryPath，并自动解压',
      refreshAfter: true,
    );
  }

  Future<void> _downloadEntry(FileInfo file) async {
    if (file.isDirectory) {
      await _downloadDirectory(file);
    } else {
      await _downloadFileEntry(file);
    }
  }

  Future<void> _downloadFileEntry(FileInfo file) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;
    final ready = await _ensureFileSession(provider);
    if (!ready) {
      return;
    }

    final downloadPlan = await _planDownloadDestination(
      itemName: file.name,
      isDirectory: false,
    );
    if (downloadPlan == null) {
      return;
    }
    final localFilePath = downloadPlan.targetPath;

    final canContinue = await _prepareLocalDestination(
      localFilePath,
      label: file.name,
      isDirectory: false,
    );
    if (!canContinue) {
      return;
    }

    final backend = _currentTransferBackend(provider);
    final cancelToken = TransferCancellationToken();
    await _runTransfer(
      cancelToken: cancelToken,
      operation: () => _fileTransferService.downloadFile(
        backend: backend,
        remoteFilePath: file.path,
        localFilePath: localFilePath,
        cancelToken: cancelToken,
        onProgress: _updateTransferProgress,
      ),
      successMessage: '文件已下载到 $localFilePath',
      refreshAfter: false,
      successOpenDirectory: downloadPlan.directoryPath,
    );
  }

  Future<void> _downloadDirectory(FileInfo file) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (provider.selectedServer == null) return;
    final ready = await _ensureFileSession(provider);
    if (!ready) {
      return;
    }

    final downloadPlan = await _planDownloadDestination(
      itemName: file.name,
      isDirectory: true,
    );
    if (downloadPlan == null) {
      return;
    }
    final localParentDirectory = downloadPlan.directoryPath;

    final localDirectoryPath = p.join(localParentDirectory, file.name);
    final canContinue = await _prepareLocalDestination(
      localDirectoryPath,
      label: file.name,
      isDirectory: true,
    );
    if (!canContinue) {
      return;
    }

    final backend = _currentTransferBackend(provider);
    final cancelToken = TransferCancellationToken();
    await _runTransfer(
      cancelToken: cancelToken,
      operation: () => _fileTransferService.downloadDirectory(
        backend: backend,
        remoteDirectoryPath: file.path,
        localParentDirectory: localParentDirectory,
        cancelToken: cancelToken,
        onProgress: _updateTransferProgress,
      ),
      successMessage: '目录已下载到 $localDirectoryPath，并自动解压',
      refreshAfter: false,
      successOpenDirectory: downloadPlan.directoryPath,
    );
  }

  Future<void> _showFileActions(FileInfo file) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  file.isDirectory
                      ? Icons.download_for_offline_outlined
                      : Icons.download_outlined,
                ),
                title: Text(file.isDirectory ? '下载并解压' : '下载'),
                subtitle: file.isDirectory
                    ? const Text('目录会先压缩传输，下载完成后自动解压')
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _downloadEntry(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(context);
                  _renameFile(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('修改权限'),
                onTap: () {
                  Navigator.pop(context);
                  _changePermissions(file);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFef4444),
                ),
                title: const Text(
                  '删除',
                  style: TextStyle(color: Color(0xFFef4444)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteFile(file);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _showTextPrompt({
    required String title,
    required String hintText,
    required String submitLabel,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: AppFieldStyles.outlined(hintText: hintText),
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: AppButtonStyles.text(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: AppButtonStyles.primary(),
            child: Text(submitLabel),
          ),
        ],
      ),
    );
  }

  Future<bool> _prepareRemoteDestination(
    String remotePath, {
    required String label,
  }) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final backend = _currentTransferBackend(provider);
    final exists = await _fileTransferService.remotePathExists(
      backend,
      remotePath,
    );
    if (!exists) {
      return true;
    }
    final confirmed = await _showReplaceConfirm(
      title: '远端存在同名项',
      message: '远端已存在 "$label"，继续后会覆盖原内容。是否继续？',
    );
    if (!confirmed) {
      return false;
    }
    await provider.deleteFileSelected(remotePath);
    return true;
  }

  Future<bool> _prepareLocalDestination(
    String localPath, {
    required String label,
    required bool isDirectory,
  }) async {
    final type = FileSystemEntity.typeSync(localPath);
    if (type == FileSystemEntityType.notFound) {
      return true;
    }
    final confirmed = await _showReplaceConfirm(
      title: '本地存在同名项',
      message: '本地已存在 "$label"，继续后会覆盖${isDirectory ? '该目录' : '该文件'}。是否继续？',
    );
    if (!confirmed) {
      return false;
    }
    await _deleteLocalPath(localPath);
    return true;
  }

  Future<bool> _showReplaceConfirm({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: AppButtonStyles.text(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: AppButtonStyles.danger(),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _runTransfer({
    required TransferCancellationToken cancelToken,
    required Future<void> Function() operation,
    required String successMessage,
    required bool refreshAfter,
    String? successOpenDirectory,
  }) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    setState(() {
      _isLoading = true;
      _lastTransferUiUpdateAt = null;
      _activeTransferToken = cancelToken;
    });
    try {
      await operation();
      if (refreshAfter) {
        await provider.requestRefreshNow(
          RefreshScope.files,
          reason: 'files-transfer-refresh',
          filePath: _currentPath,
        );
        if (mounted) {
          _applyCache(provider);
        }
      }
      if (mounted) {
        _showSnackBar(
          successMessage,
          actionLabel: successOpenDirectory == null ? null : '打开下载文件夹',
          onAction: successOpenDirectory == null
              ? null
              : () => _openDirectory(successOpenDirectory),
        );
      }
    } on TransferCancelledException {
      if (mounted) {
        _showSnackBar('已终止当前传输任务');
      }
    } catch (error) {
      if (mounted) {
        _showSnackBar(_friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (identical(_activeTransferToken, cancelToken)) {
            _activeTransferToken = null;
          }
        });
      }
    }
  }

  Future<void> _cancelActiveTransfer() async {
    final token = _activeTransferToken;
    if (token == null || token.isCancelled) {
      return;
    }
    await token.cancel();
  }

  Future<void> _deleteLocalPath(String localPath) async {
    final type = FileSystemEntity.typeSync(localPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(localPath).delete(recursive: true);
      return;
    }
    if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link) {
      await File(localPath).delete();
    }
  }

  Future<String> _resolveDefaultDownloadDirectory() async {
    final cached = _defaultDownloadDirectory;
    if (cached != null && cached.trim().isNotEmpty) {
      await Directory(cached).create(recursive: true);
      return cached;
    }

    final downloadsDirectory = await getDownloadsDirectory();
    final resolvedPath =
        downloadsDirectory?.path ??
        _fallbackHomeDirectory() ??
        Directory.current.path;
    await Directory(resolvedPath).create(recursive: true);
    return resolvedPath;
  }

  String? _fallbackHomeDirectory() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'];
    }
    return Platform.environment['HOME'];
  }

  Future<String?> _pickLocalFilePath() async {
    try {
      final xFile = await openFile(
        initialDirectory: await _resolveDefaultDownloadDirectory(),
        confirmButtonText: '选择文件',
      );
      return xFile?.path;
    } catch (error) {
      _showSnackBar('打开文件选择窗口失败: ${_friendlyError(error)}');
      return null;
    }
  }

  Future<String?> _pickLocalDirectoryPath() async {
    try {
      return await getDirectoryPath(
        initialDirectory: await _resolveDefaultDownloadDirectory(),
        confirmButtonText: '选择文件夹',
      );
    } catch (error) {
      _showSnackBar('打开文件夹选择窗口失败: ${_friendlyError(error)}');
      return null;
    }
  }

  Future<_DownloadPlan?> _planDownloadDestination({
    required String itemName,
    required bool isDirectory,
  }) async {
    final defaultDirectory = await _resolveDefaultDownloadDirectory();
    if (!mounted) {
      return null;
    }

    String selectedDirectory = defaultDirectory;
    return showDialog<_DownloadPlan>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final targetPath = p.join(selectedDirectory, itemName);
            return AlertDialog(
              title: Text(isDirectory ? '下载目录' : '下载文件'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFf8fafc),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFe2e8f0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isDirectory
                                ? Icons.folder_zip_outlined
                                : Icons.download_outlined,
                            color: isDirectory
                                ? const Color(0xFFd97706)
                                : const Color(0xFF2563eb),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isDirectory ? '默认下载到系统下载目录' : '默认保存到系统下载目录',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1a2332),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isDirectory
                                      ? '目录会先压缩传输，下载完成后自动解压到目标目录。'
                                      : '下载完成后可直接打开所在文件夹继续查看。',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748b),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '保存目录',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFdce3eb)),
                      ),
                      child: Text(
                        selectedDirectory,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Monospace',
                          color: Color(0xFF1a2332),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final pickedDirectory = await getDirectoryPath(
                              initialDirectory: selectedDirectory,
                              confirmButtonText: '选择下载目录',
                            );
                            if (pickedDirectory == null ||
                                pickedDirectory.trim().isEmpty) {
                              return;
                            }
                            setDialogState(
                              () => selectedDirectory = pickedDirectory,
                            );
                          },
                          style: AppButtonStyles.text(),
                          icon: const Icon(
                            Icons.folder_open_outlined,
                            size: 16,
                          ),
                          label: const Text('更改目录'),
                        ),
                        TextButton.icon(
                          onPressed: selectedDirectory == defaultDirectory
                              ? null
                              : () => setDialogState(
                                  () => selectedDirectory = defaultDirectory,
                                ),
                          style: AppButtonStyles.text(),
                          icon: const Icon(Icons.restart_alt, size: 16),
                          label: const Text('恢复默认'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '最终保存位置',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFeff6ff),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        targetPath,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Monospace',
                          color: Color(0xFF1d4ed8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: AppButtonStyles.text(),
                  child: const Text('取消'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _DownloadPlan(
                      directoryPath: selectedDirectory,
                      targetPath: targetPath,
                    ),
                  ),
                  style: AppButtonStyles.primary(),
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('开始下载'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openDirectory(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        _showSnackBar('目录不存在: $directoryPath');
        return;
      }
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [directoryPath]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [directoryPath]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [directoryPath]);
      } else {
        _showSnackBar('当前平台暂不支持自动打开文件夹');
      }
    } catch (error) {
      _showSnackBar('打开文件夹失败: ${_friendlyError(error)}');
    }
  }

  void _updateTransferProgress(FileTransferProgress progress) {
    if (!mounted) {
      return;
    }
    final previous = _transferProgress;
    final now = DateTime.now();
    final stageChanged =
        previous == null ||
        previous.type != progress.type ||
        previous.stage != progress.stage ||
        previous.sourceLabel != progress.sourceLabel ||
        previous.targetLabel != progress.targetLabel ||
        progress.isFinished;
    final enoughBytesChanged =
        previous == null ||
        (progress.transferredBytes - previous.transferredBytes).abs() >=
            64 * 1024 ||
        progress.totalBytes == null ||
        progress.transferredBytes >= progress.totalBytes!;
    final enoughTimePassed =
        _lastTransferUiUpdateAt == null ||
        now.difference(_lastTransferUiUpdateAt!) >=
            const Duration(milliseconds: 120);

    if (!stageChanged && !enoughBytesChanged && !enoughTimePassed) {
      return;
    }

    _lastTransferUiUpdateAt = now;
    setState(() => _transferProgress = progress);
  }

  void _showSnackBar(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }

  String _friendlyError(Object error) {
    final raw = error.toString();
    return raw.startsWith('Exception: ') ? raw.substring(11) : raw;
  }

  String _buildPath(String childName) {
    if (_currentPath == '/') {
      return '/$childName';
    }
    return '$_currentPath/$childName';
  }

  String _normalizePath(String path) {
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

  String _permissionToOctal(String permissionString) {
    if (permissionString.length < 10) {
      return '';
    }

    String tripletToDigit(String triplet) {
      var total = 0;
      if (triplet[0] == 'r') {
        total += 4;
      }
      if (triplet[1] == 'w') {
        total += 2;
      }
      if (triplet[2] == 'x' || triplet[2] == 's' || triplet[2] == 't') {
        total += 1;
      }
      return total.toString();
    }

    return [
      tripletToDigit(permissionString.substring(1, 4)),
      tripletToDigit(permissionString.substring(4, 7)),
      tripletToDigit(permissionString.substring(7, 10)),
    ].join();
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

  String _transferStageLabel(FileTransferStage stage) {
    switch (stage) {
      case FileTransferStage.preparing:
        return '准备中';
      case FileTransferStage.transferring:
        return '传输中';
      case FileTransferStage.extracting:
        return '解压中';
      case FileTransferStage.cleaning:
        return '清理中';
      case FileTransferStage.completed:
        return '已完成';
      case FileTransferStage.cancelled:
        return '已取消';
      case FileTransferStage.failed:
        return '失败';
    }
  }

  Color _transferStageColor(FileTransferStage stage) {
    switch (stage) {
      case FileTransferStage.completed:
        return const Color(0xFF059669);
      case FileTransferStage.cancelled:
        return const Color(0xFFf59e0b);
      case FileTransferStage.failed:
        return const Color(0xFFdc2626);
      case FileTransferStage.extracting:
        return const Color(0xFFd97706);
      case FileTransferStage.preparing:
      case FileTransferStage.transferring:
      case FileTransferStage.cleaning:
        return const Color(0xFF2563eb);
    }
  }

  double? _displayProgressFraction(FileTransferProgress progress) {
    switch (progress.stage) {
      case FileTransferStage.preparing:
        return progress.compressed ? 0.08 : 0.02;
      case FileTransferStage.transferring:
        final fraction = progress.fraction;
        if (fraction == null) {
          return progress.compressed ? 0.2 : null;
        }
        if (!progress.compressed) {
          return fraction;
        }
        return 0.1 + (fraction * 0.75);
      case FileTransferStage.extracting:
        return progress.compressed ? 0.9 : 1.0;
      case FileTransferStage.cleaning:
        return progress.compressed ? 0.97 : 1.0;
      case FileTransferStage.completed:
        return 1.0;
      case FileTransferStage.cancelled:
        return progress.fraction;
      case FileTransferStage.failed:
        return progress.fraction;
    }
  }

  String _progressCaption(FileTransferProgress progress) {
    final fraction = _displayProgressFraction(progress);
    if (fraction == null) {
      return '等待统计...';
    }
    return '${(fraction * 100).toStringAsFixed(0)}%';
  }

  String? _completedDownloadDirectory(FileTransferProgress progress) {
    if (!progress.isFinished || progress.stage != FileTransferStage.completed) {
      return null;
    }
    switch (progress.type) {
      case FileTransferType.downloadFile:
        return p.dirname(progress.targetLabel);
      case FileTransferType.downloadDirectory:
        return progress.targetLabel;
      case FileTransferType.uploadFile:
      case FileTransferType.uploadDirectory:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFFf0f4f8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final reservedHeight = _transferProgress == null ? 250.0 : 470.0;
          final listHeight = (constraints.maxHeight - reservedHeight).clamp(
            220.0,
            double.infinity,
          );
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  _buildPathBar(provider),
                  const SizedBox(height: 16),
                  _buildOverviewCards(),
                  if (_transferProgress != null) ...[
                    const SizedBox(height: 16),
                    _buildTransferCard(),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(height: listHeight, child: _buildFilesList()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPathBar(AppProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              AppIconActionButton(
                icon: Icons.arrow_back,
                tooltip: '返回上一级',
                onPressed: _currentPath != '/' && !_hasActiveTransfer
                    ? _goBack
                    : null,
                foregroundColor: _currentPath != '/' && !_hasActiveTransfer
                    ? const Color(0xFF2563eb)
                    : const Color(0xFF9ca3af),
                backgroundColor: const Color(0xFFeff6ff),
                iconSize: 18,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _pathController,
                  enabled:
                      provider.selectedServer != null &&
                      !_isLoading &&
                      !_hasActiveTransfer,
                  decoration: AppFieldStyles.outlined(
                    hintText: '输入绝对路径，例如 /home/ubuntu',
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'Monospace'),
                  onSubmitted: (_) {
                    if (_hasActiveTransfer) {
                      return;
                    }
                    _submitPath();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed:
                      provider.selectedServer == null ||
                          _isLoading ||
                          _hasActiveTransfer
                      ? null
                      : _submitPath,
                  style: AppButtonStyles.primary(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('确认路径'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppControlShell(
                  child: TextField(
                    enabled:
                        provider.selectedServer != null &&
                        !_isLoading &&
                        !_hasActiveTransfer,
                    readOnly: _hasActiveTransfer,
                    decoration: AppFieldStyles.toolbarInput(
                      hintText: '搜索名称、权限或修改时间...',
                    ),
                    onChanged: (text) {
                      setState(() => _searchText = text);
                      _reloadFiles();
                    },
                  ),
                ),
              ),
            ],
          ),
          if (_pathErrorMessage != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _pathErrorMessage!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFdc2626)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              ElevatedButton(
                onPressed:
                    provider.selectedServer != null &&
                        !_isLoading &&
                        !_hasActiveTransfer
                    ? _uploadFile
                    : null,
                style: AppButtonStyles.primary(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: const Text('上传文件'),
              ),
              ElevatedButton(
                onPressed:
                    provider.selectedServer != null &&
                        !_isLoading &&
                        !_hasActiveTransfer
                    ? _uploadDirectory
                    : null,
                style: AppButtonStyles.secondary(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: const Text('上传目录'),
              ),
              ElevatedButton(
                onPressed:
                    provider.selectedServer != null &&
                        !_isLoading &&
                        !_hasActiveTransfer
                    ? _createDirectory
                    : null,
                style: AppButtonStyles.primary(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: const Text('新建文件夹'),
              ),
              ElevatedButton(
                onPressed:
                    provider.selectedServer != null &&
                        !_isLoading &&
                        !_hasActiveTransfer
                    ? _createFile
                    : null,
                style: AppButtonStyles.secondary(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: const Text('新建文件'),
              ),
              ElevatedButton(
                onPressed:
                    provider.selectedServer == null ||
                        _isLoading ||
                        _hasActiveTransfer
                    ? null
                    : refresh,
                style: AppButtonStyles.subtle(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF6b7c93),
                        ),
                      )
                    : const Text('刷新文件列表'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 32) / 3;
        final resolvedWidth = cardWidth < 260
            ? constraints.maxWidth
            : cardWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: resolvedWidth,
              child: _buildInfoCard(
                title: '当前目录',
                value: _currentPath,
                hint: '支持直接输入绝对路径跳转',
                accent: const Color(0xFF2563eb),
              ),
            ),
            SizedBox(
              width: resolvedWidth,
              child: _buildInfoCard(
                title: '当前条目',
                value: '${_files.length}',
                hint: '目录默认排在文件前面',
                accent: const Color(0xFF059669),
              ),
            ),
            SizedBox(
              width: resolvedWidth,
              child: _buildInfoCard(
                title: '默认下载目录',
                value: _defaultDownloadDirectory ?? '定位中...',
                hint: '下载默认保存到系统下载目录，可在下载前更改',
                accent: const Color(0xFFd97706),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String value,
    required String hint,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94a3b8)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferCard() {
    final progress = _transferProgress!;
    final fraction = _displayProgressFraction(progress);
    final stageColor = _transferStageColor(progress.stage);
    final completedDownloadDirectory = _completedDownloadDirectory(progress);
    final isFinished = progress.isFinished;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: stageColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _transferStageLabel(progress.stage),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: stageColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  progress.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (progress.compressed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFfffbeb),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'tar.gz 压缩传输',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFd97706),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            progress.detail,
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 12),
          if (!isFinished)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFeff6ff),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: Color(0xFF2563eb)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '传输进行中，已暂时锁定目录跳转、刷新和重复操作，避免状态冲突。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1d4ed8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!isFinished) const SizedBox(height: 12),
          if (!isFinished) ...[
            _buildTransferMetaRow('来源', progress.sourceLabel),
            const SizedBox(height: 6),
          ],
          _buildTransferMetaRow('目标', progress.targetLabel),
          if (!isFinished) const SizedBox(height: 12),
          if (!isFinished && fraction != null) ...[
            AppProgressBar(
              value: fraction,
              color: stageColor,
              height: 10,
              radius: 5,
              backgroundColor: const Color(0xFFe2e8f0),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _progressCaption(progress),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1a2332),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_formatBytes(progress.transferredBytes)} / ${_formatBytes(progress.totalBytes ?? 0)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748b),
                  ),
                ),
              ],
            ),
          ] else if (!isFinished) ...[
            const Text(
              '正在处理，请稍候...',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748b)),
            ),
          ],
          if (progress.message != null && progress.message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              progress.message!,
              style: TextStyle(
                fontSize: 11,
                color: progress.stage == FileTransferStage.failed
                    ? const Color(0xFFdc2626)
                    : const Color(0xFF475569),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!isFinished)
                ElevatedButton.icon(
                  onPressed: _cancelActiveTransfer,
                  style: AppButtonStyles.danger(),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('终止传输'),
                ),
              if (completedDownloadDirectory != null)
                ElevatedButton.icon(
                  onPressed: () => _openDirectory(completedDownloadDirectory),
                  style: AppButtonStyles.secondary(),
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: const Text('打开下载文件夹'),
                ),
              if (isFinished)
                TextButton(
                  onPressed: () => setState(() => _transferProgress = null),
                  style: AppButtonStyles.text(),
                  child: const Text('收起'),
                ),
              Text(
                isFinished ? '传输结果会保留，方便回来后继续查看。' : '传输过程中可切换页面，返回后会继续显示当前进度。',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748b)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransferMetaRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94a3b8)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF1a2332),
              fontFamily: 'Monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilesList() {
    if (_files.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFe2e8f0)),
        ),
        child: const Center(
          child: Text(
            '暂无文件数据，或后台尚未采集完成',
            style: TextStyle(fontSize: 13, color: Color(0xFF6b7c93)),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFe2e8f0))),
            ),
            child: Row(
              children: [
                SortHeaderCell(
                  label: '名称',
                  active: _sortBy == 'name',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('name'),
                ),
                SortHeaderCell(
                  label: '类型',
                  active: _sortBy == 'type',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('type'),
                ),
                SortHeaderCell(
                  label: '大小',
                  active: _sortBy == 'size',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('size'),
                ),
                SortHeaderCell(
                  label: '修改时间',
                  active: _sortBy == 'modified',
                  ascending: _sortAscending,
                  onTap: () => _toggleSort('modified'),
                ),
                const Expanded(
                  child: Text(
                    '操作',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6b7c93),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final file = _files[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFf0f4f8)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              file.isDirectory
                                  ? Icons.folder
                                  : Icons.description,
                              color: file.isDirectory
                                  ? const Color(0xFFf59e0b)
                                  : const Color(0xFF6b7c93),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (file.isDirectory && !_hasActiveTransfer) {
                                    _navigateTo(file.path);
                                  }
                                },
                                child: Text(
                                  file.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: file.isDirectory
                                        ? const Color(0xFF2563eb)
                                        : Colors.black,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          file.isDirectory ? '文件夹' : '文件',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6b7c93),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          file.size,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          file.modified,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6b7c93),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            AppIconActionButton(
                              icon: file.isDirectory
                                  ? Icons.download_for_offline_outlined
                                  : Icons.download_outlined,
                              tooltip: file.isDirectory ? '下载目录' : '下载文件',
                              onPressed: _isLoading || _hasActiveTransfer
                                  ? null
                                  : () => _downloadEntry(file),
                              foregroundColor: file.isDirectory
                                  ? const Color(0xFFd97706)
                                  : const Color(0xFF2563eb),
                              backgroundColor: file.isDirectory
                                  ? const Color(0xFFfffbeb)
                                  : const Color(0xFFeff6ff),
                            ),
                            const SizedBox(width: 10),
                            AppIconActionButton(
                              icon: Icons.more_horiz,
                              tooltip: '更多操作',
                              onPressed: _isLoading || _hasActiveTransfer
                                  ? null
                                  : () => _showFileActions(file),
                              foregroundColor: const Color(0xFF2563eb),
                              backgroundColor: const Color(0xFFeff6ff),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadPlan {
  final String directoryPath;
  final String targetPath;

  const _DownloadPlan({required this.directoryPath, required this.targetPath});
}
