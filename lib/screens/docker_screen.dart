import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/refresh_scope.dart';
import '../models/query_options.dart';
import '../providers/app_provider.dart';
import '../models/server.dart';
import '../widgets/app_button_styles.dart';
import '../widgets/adaptive_page_layout.dart';
import '../widgets/sort_header_cell.dart';

class DockerScreen extends StatefulWidget {
  const DockerScreen({super.key});

  @override
  State<DockerScreen> createState() => DockerScreenState();
}

class DockerScreenState extends State<DockerScreen> {
  List<DockerContainer> _containers = [];
  List<DockerImage> _images = [];
  String _searchText = '';
  bool _isLoading = false;
  bool _showImages = false;
  bool _dockerInstalled = true;
  String? _lastServerId;
  String _containerSortBy = 'name';
  bool _containerSortAscending = true;
  String _imageSortBy = 'created';
  bool _imageSortAscending = false;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFDC2626) : null,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromCache();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<AppProvider>(context);
    if (_lastServerId != provider.selectedServer?.id) {
      _lastServerId = provider.selectedServer?.id;
      setState(() {
        _containers = [];
        _images = [];
        _dockerInstalled = true;
      });
      _syncFromCache();
      provider.onPageEnter(RefreshScope.docker);
    }
  }

  void _syncFromCache() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final cache = provider.currentCache;
    final capability = provider.storageService;
    if (provider.selectedServer == null || cache == null) {
      setState(() {
        _containers = [];
        _images = [];
        _dockerInstalled = true;
      });
      return;
    }

    capability.getCapability(provider.selectedServer!.id).then((value) {
      if (!mounted) return;
      setState(() {
        _dockerInstalled = value?['dockerInstalled'] as bool? ?? true;
      });
      _reloadDockerLists();
    });
  }

  Future<void> _reloadDockerLists() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final serverId = provider.selectedServer?.id;
    if (serverId == null) {
      if (!mounted) return;
      setState(() {
        _containers = [];
        _images = [];
      });
      return;
    }
    final containers = await provider.storageService.queryDockerContainers(
      serverId: serverId,
      options: QueryOptions(
        keyword: _searchText,
        sortBy: _containerSortBy,
        direction: _containerSortAscending
            ? SortDirection.ascending
            : SortDirection.descending,
      ),
    );
    final images = await provider.storageService.queryDockerImages(
      serverId: serverId,
      options: QueryOptions(
        keyword: _searchText,
        sortBy: _imageSortBy,
        direction: _imageSortAscending
            ? SortDirection.ascending
            : SortDirection.descending,
      ),
    );
    if (!mounted) return;
    setState(() {
      _containers = containers;
      _images = images;
    });
  }

  Future<void> refresh() async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    setState(() => _isLoading = true);
    await provider.requestRefreshNow(
      RefreshScope.docker,
      reason: 'docker-refresh',
    );
    _syncFromCache();
    setState(() => _isLoading = false);
  }

  Future<void> _manageContainer(String name, String action) async {
    final provider = Provider.of<AppProvider>(context, listen: false);
    if (!provider.isConnected) return;

    setState(() => _isLoading = true);
    try {
      await provider.manageContainerSelected(
        containerId: name,
        action: action,
      );
      await provider.requestRefreshNow(
        RefreshScope.docker,
        reason: 'docker-manage',
      );
      _syncFromCache();
      _showMessage('容器 $name 已执行 $action');
    } catch (error) {
      _showMessage('容器操作失败：$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeContainer(String name) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除容器'),
        content: Text('确定要删除容器 $name 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _manageContainer(name, 'rm -f');
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  bool _isRunning(DockerContainer container) {
    return container.status.toLowerCase().startsWith('up');
  }

  Future<void> _removeImage(String imageId) async {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final provider = Provider.of<AppProvider>(dialogContext, listen: false);
        final navigator = Navigator.of(dialogContext);
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('确定要删除此镜像吗？'),
          actions: [
            TextButton(onPressed: navigator.pop, child: const Text('取消')),
            TextButton(
              onPressed: () async {
                setState(() => _isLoading = true);
                try {
                  await provider.deleteImageSelected(imageId: imageId);
                  await provider.requestRefreshNow(
                    RefreshScope.docker,
                    reason: 'docker-delete-image',
                  );
                  _syncFromCache();
                  _showMessage('镜像已删除');
                } catch (error) {
                  _showMessage('删除镜像失败：$error', isError: true);
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                }
                navigator.pop();
              },
              style: AppButtonStyles.textDanger(),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  List<DockerContainer> get _filteredContainers {
    return _containers;
  }

  List<DockerImage> get _filteredImages {
    return _images;
  }

  void _toggleContainerSort(String sortBy) {
    setState(() {
      if (_containerSortBy == sortBy) {
        _containerSortAscending = !_containerSortAscending;
      } else {
        _containerSortBy = sortBy;
        _containerSortAscending =
            sortBy == 'name' || sortBy == 'image' || sortBy == 'status';
      }
    });
    _reloadDockerLists();
  }

  void _toggleImageSort(String sortBy) {
    setState(() {
      if (_imageSortBy == sortBy) {
        _imageSortAscending = !_imageSortAscending;
      } else {
        _imageSortBy = sortBy;
        _imageSortAscending = sortBy == 'name' || sortBy == 'tag';
      }
    });
    _reloadDockerLists();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);

    return AdaptivePageLayout(
      estimatedReservedHeight: 220,
      minBodyHeight: 260,
      header: [
        _buildTopBar(provider),
        const SizedBox(height: 16),
        _buildStatsCards(),
        const SizedBox(height: 16),
      ],
      body: _showImages ? _buildImagesList() : _buildContainersList(),
    );
  }

  Widget _buildTopBar(AppProvider provider) {
    return Row(
      children: [
        Expanded(
          child: AppControlShell(
            child: TextField(
              decoration: AppFieldStyles.toolbarInput(hintText: '搜索容器或镜像...'),
              onChanged: (text) {
                setState(() => _searchText = text);
                _reloadDockerLists();
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFdce3eb)),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: TextButton(
                  onPressed: () => setState(() => _showImages = false),
                  child: Text(
                    '容器',
                    style: TextStyle(
                      fontSize: 12,
                      color: !_showImages
                          ? const Color(0xFF2563eb)
                          : const Color(0xFF6b7c93),
                      fontWeight: !_showImages
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              const VerticalDivider(color: Color(0xFFdce3eb)),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: TextButton(
                  onPressed: () => setState(() => _showImages = true),
                  child: Text(
                    '镜像',
                    style: TextStyle(
                      fontSize: 12,
                      color: _showImages
                          ? const Color(0xFF2563eb)
                          : const Color(0xFF6b7c93),
                      fontWeight: _showImages
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: provider.selectedServer == null ? null : refresh,
          style: AppButtonStyles.primary(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('刷新 Docker'),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.docker.key];
    final running = _containers.where(_isRunning).length;
    final stopped = _containers.where((c) => !_isRunning(c)).length;
    final images = _images.length;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFe2e8f0)),
            ),
            child: Column(
              children: [
                const Text(
                  '运行中容器',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
                ),
                const SizedBox(height: 8),
                Text(
                  updatedAt == null ? running.toString() : '$running',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10b981),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFe2e8f0)),
            ),
            child: Column(
              children: [
                const Text(
                  '已停止容器',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
                ),
                const SizedBox(height: 8),
                Text(
                  stopped.toString(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6b7c93),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFe2e8f0)),
            ),
            child: Column(
              children: [
                const Text(
                  '镜像数量',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6b7c93)),
                ),
                const SizedBox(height: 8),
                Text(
                  images.toString(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2563eb),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContainersList() {
    if (!_dockerInstalled) {
      return _buildEmptyState('当前服务器未检测到 Docker 环境');
    }

    if (_filteredContainers.isEmpty) {
      return _buildEmptyState('当前服务器暂无容器');
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
                  active: _containerSortBy == 'name',
                  ascending: _containerSortAscending,
                  onTap: () => _toggleContainerSort('name'),
                ),
                SortHeaderCell(
                  label: '镜像',
                  active: _containerSortBy == 'image',
                  ascending: _containerSortAscending,
                  onTap: () => _toggleContainerSort('image'),
                ),
                SortHeaderCell(
                  label: '状态',
                  active: _containerSortBy == 'status',
                  ascending: _containerSortAscending,
                  onTap: () => _toggleContainerSort('status'),
                ),
                const Expanded(
                  child: Text(
                    '端口',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6b7c93),
                    ),
                  ),
                ),
                SortHeaderCell(
                  label: '资源占用',
                  active:
                      _containerSortBy == 'cpu' || _containerSortBy == 'memory',
                  ascending: _containerSortAscending,
                  onTap: () => _toggleContainerSort(
                    _containerSortBy == 'cpu' ? 'memory' : 'cpu',
                  ),
                ),
                Expanded(
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
              itemCount: _filteredContainers.length,
              itemBuilder: (context, index) {
                final container = _filteredContainers[index];
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
                        child: Text(
                          container.name,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          container.image,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6b7c93),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _isRunning(container)
                                ? const Color(0xFFecfdf5)
                                : const Color(0xFFf0f4f8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _isRunning(container) ? '运行中' : '已停止',
                            style: TextStyle(
                              fontSize: 11,
                              color: _isRunning(container)
                                  ? const Color(0xFF10b981)
                                  : const Color(0xFF6b7c93),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          container.ports.isNotEmpty
                              ? container.ports.join(', ')
                              : '-',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${container.cpuUsage} / ${container.memoryUsage}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            AppIconActionButton(
                              icon: Icons.play_arrow,
                              tooltip: '启动容器',
                              onPressed: () => _manageContainer(container.name, 'start'),
                              foregroundColor: const Color(0xFF10b981),
                              backgroundColor: const Color(0xFFecfdf5),
                            ),
                            const SizedBox(width: 8),
                            AppIconActionButton(
                              icon: Icons.stop,
                              tooltip: '停止容器',
                              onPressed: () => _manageContainer(container.name, 'stop'),
                              foregroundColor: const Color(0xFFef4444),
                              backgroundColor: const Color(0xFFfef2f2),
                            ),
                            const SizedBox(width: 8),
                            AppIconActionButton(
                              icon: Icons.refresh,
                              tooltip: '重启容器',
                              onPressed: () => _manageContainer(container.name, 'restart'),
                              foregroundColor: const Color(0xFF2563eb),
                              backgroundColor: const Color(0xFFeff6ff),
                            ),
                            const SizedBox(width: 8),
                            AppIconActionButton(
                              icon: Icons.delete_outline,
                              tooltip: '删除容器',
                              onPressed: () => _removeContainer(container.name),
                              foregroundColor: const Color(0xFFef4444),
                              backgroundColor: const Color(0xFFfef2f2),
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

  Widget _buildImagesList() {
    if (!_dockerInstalled) {
      return _buildEmptyState('当前服务器未检测到 Docker 环境');
    }

    if (_filteredImages.isEmpty) {
      return _buildEmptyState('当前服务器暂无镜像');
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
                  label: '镜像名称',
                  active: _imageSortBy == 'name',
                  ascending: _imageSortAscending,
                  onTap: () => _toggleImageSort('name'),
                ),
                SortHeaderCell(
                  label: '标签',
                  active: _imageSortBy == 'tag',
                  ascending: _imageSortAscending,
                  onTap: () => _toggleImageSort('tag'),
                ),
                const Expanded(
                  child: Text(
                    'ID',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6b7c93),
                    ),
                  ),
                ),
                SortHeaderCell(
                  label: '大小',
                  active: _imageSortBy == 'size',
                  ascending: _imageSortAscending,
                  onTap: () => _toggleImageSort('size'),
                ),
                SortHeaderCell(
                  label: '创建时间',
                  active: _imageSortBy == 'created',
                  ascending: _imageSortAscending,
                  onTap: () => _toggleImageSort('created'),
                ),
                Expanded(
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
              itemCount: _filteredImages.length,
              itemBuilder: (context, index) {
                final image = _filteredImages[index];
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
                        child: Text(
                          image.name,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          image.tag,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6b7c93),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          image.id.substring(0, 12),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          image.size,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          image.created,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AppIconActionButton(
                            icon: Icons.delete_outline,
                            tooltip: '删除镜像',
                            onPressed: () => _removeImage(image.id),
                            foregroundColor: const Color(0xFFef4444),
                            backgroundColor: const Color(0xFFfef2f2),
                          ),
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

  Widget _buildEmptyState(String message) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    final updatedAt =
        provider.currentCache?.scopeUpdatedAt[RefreshScope.docker.key];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFe2e8f0)),
      ),
      child: Center(
        child: Text(
          updatedAt == null
              ? '$message\n等待后台采集...'
              : '$message\n最后更新: ${_formatTimestamp(updatedAt)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF6b7c93)),
        ),
      ),
    );
  }

  String _formatTimestamp(String raw) {
    final time = DateTime.tryParse(raw);
    if (time == null) {
      return raw;
    }
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
