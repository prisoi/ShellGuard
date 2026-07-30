import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/ssh_manager.dart';

enum FileTransferType {
  uploadFile,
  uploadDirectory,
  downloadFile,
  downloadDirectory,
}

enum FileTransferStage {
  preparing,
  transferring,
  extracting,
  cleaning,
  completed,
  cancelled,
  failed,
}

class FileTransferProgress {
  final FileTransferType type;
  final FileTransferStage stage;
  final String title;
  final String detail;
  final String sourceLabel;
  final String targetLabel;
  final int transferredBytes;
  final int? totalBytes;
  final bool compressed;
  final String? message;

  const FileTransferProgress({
    required this.type,
    required this.stage,
    required this.title,
    required this.detail,
    required this.sourceLabel,
    required this.targetLabel,
    this.transferredBytes = 0,
    this.totalBytes,
    this.compressed = false,
    this.message,
  });

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (transferredBytes / total).clamp(0.0, 1.0);
  }

  bool get isFinished =>
      stage == FileTransferStage.completed ||
      stage == FileTransferStage.cancelled ||
      stage == FileTransferStage.failed;
}

class FileTransferService {
  const FileTransferService();

  Future<bool> remotePathExists(
    SshManager sshManager,
    String remotePath,
  ) async {
    return sshManager.withSftp((sftp) async {
      try {
        await sftp.stat(remotePath);
        return true;
      } catch (_) {
        return false;
      }
    });
  }

  Future<void> uploadFile({
    required SshManager sshManager,
    required String localFilePath,
    required String remoteFilePath,
    void Function(FileTransferProgress progress)? onProgress,
    TransferCancellationToken? cancelToken,
  }) async {
    final file = File(localFilePath);
    final totalBytes = await file.length();
    final title = '上传文件';
    final sourceLabel = localFilePath;
    final targetLabel = remoteFilePath;

    try {
      _throwIfCancelled(cancelToken);
      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.uploadFile,
          stage: FileTransferStage.preparing,
          title: title,
          detail: '正在检查目标目录...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          totalBytes: totalBytes,
        ),
      );

      await _ensureRemoteDirectory(sshManager, _remoteDirname(remoteFilePath));
      _throwIfCancelled(cancelToken);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.uploadFile,
          stage: FileTransferStage.transferring,
          title: title,
          detail: '正在上传文件...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          totalBytes: totalBytes,
        ),
      );

      await sshManager.uploadLocalFile(
        localFilePath,
        remoteFilePath,
        cancelToken: cancelToken,
        onProgress: (bytes) {
          _emit(
            onProgress,
            FileTransferProgress(
              type: FileTransferType.uploadFile,
              stage: FileTransferStage.transferring,
              title: title,
              detail: '正在上传文件...',
              sourceLabel: sourceLabel,
              targetLabel: targetLabel,
              transferredBytes: bytes,
              totalBytes: totalBytes,
            ),
          );
        },
      );
      _throwIfCancelled(cancelToken);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.uploadFile,
          stage: FileTransferStage.completed,
          title: title,
          detail: '文件上传完成',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          transferredBytes: totalBytes,
          totalBytes: totalBytes,
          message: '已上传 ${p.basename(localFilePath)}',
        ),
      );
    } on TransferCancelledException catch (error) {
      await _safeDeleteRemoteFile(sshManager, remoteFilePath);
      _emitCancelled(
        onProgress,
        FileTransferType.uploadFile,
        title,
        sourceLabel,
        targetLabel,
        error,
      );
      rethrow;
    } catch (error) {
      _emitFailure(
        onProgress,
        FileTransferType.uploadFile,
        title,
        sourceLabel,
        targetLabel,
        error,
      );
      rethrow;
    }
  }

  Future<void> downloadFile({
    required SshManager sshManager,
    required String remoteFilePath,
    required String localFilePath,
    void Function(FileTransferProgress progress)? onProgress,
    TransferCancellationToken? cancelToken,
  }) async {
    final title = '下载文件';
    final sourceLabel = remoteFilePath;
    final targetLabel = localFilePath;

    try {
      _throwIfCancelled(cancelToken);
      final totalBytes = await sshManager.statRemoteFileSize(remoteFilePath);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.downloadFile,
          stage: FileTransferStage.transferring,
          title: title,
          detail: '正在下载文件...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          totalBytes: totalBytes,
        ),
      );

      await sshManager.downloadRemoteFile(
        remoteFilePath,
        localFilePath,
        cancelToken: cancelToken,
        onProgress: (bytes) {
          _emit(
            onProgress,
            FileTransferProgress(
              type: FileTransferType.downloadFile,
              stage: FileTransferStage.transferring,
              title: title,
              detail: '正在下载文件...',
              sourceLabel: sourceLabel,
              targetLabel: targetLabel,
              transferredBytes: bytes,
              totalBytes: totalBytes,
            ),
          );
        },
      );
      _throwIfCancelled(cancelToken);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.downloadFile,
          stage: FileTransferStage.completed,
          title: title,
          detail: '文件下载完成',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          transferredBytes: totalBytes ?? 0,
          totalBytes: totalBytes,
          message: '已保存到 ${p.basename(localFilePath)}',
        ),
      );
    } on TransferCancelledException catch (error) {
      await _safeDeleteLocalFile(localFilePath);
      _emitCancelled(
        onProgress,
        FileTransferType.downloadFile,
        title,
        sourceLabel,
        targetLabel,
        error,
      );
      rethrow;
    } catch (error) {
      _emitFailure(
        onProgress,
        FileTransferType.downloadFile,
        title,
        sourceLabel,
        targetLabel,
        error,
      );
      rethrow;
    }
  }

  Future<void> uploadDirectory({
    required SshManager sshManager,
    required String localDirectoryPath,
    required String remoteDirectoryPath,
    void Function(FileTransferProgress progress)? onProgress,
    TransferCancellationToken? cancelToken,
  }) async {
    final title = '上传目录';
    final sourceLabel = localDirectoryPath;
    final targetLabel = remoteDirectoryPath;
    final tempDir = await Directory.systemTemp.createTemp('shellguard-upload-');
    final archiveName =
        '${p.basename(localDirectoryPath)}-${DateTime.now().millisecondsSinceEpoch}.tar.gz';
    final localArchivePath = p.join(tempDir.path, archiveName);
    final remoteArchivePath =
        '/tmp/shellguard-upload-${DateTime.now().microsecondsSinceEpoch}.tar.gz';

    try {
      _throwIfCancelled(cancelToken);
      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.uploadDirectory,
          stage: FileTransferStage.preparing,
          title: title,
          detail: '正在将目录打包为 tar.gz...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          compressed: true,
        ),
      );

      await _createTarArchive(localDirectoryPath, localArchivePath);
      _throwIfCancelled(cancelToken);
      final totalBytes = await File(localArchivePath).length();

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.uploadDirectory,
          stage: FileTransferStage.transferring,
          title: title,
          detail: '正在上传压缩包...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          totalBytes: totalBytes,
          compressed: true,
        ),
      );

      await sshManager.uploadLocalFile(
        localArchivePath,
        remoteArchivePath,
        cancelToken: cancelToken,
        onProgress: (bytes) {
          _emit(
            onProgress,
            FileTransferProgress(
              type: FileTransferType.uploadDirectory,
              stage: FileTransferStage.transferring,
              title: title,
              detail: '正在上传压缩包...',
              sourceLabel: sourceLabel,
              targetLabel: targetLabel,
              transferredBytes: bytes,
              totalBytes: totalBytes,
              compressed: true,
            ),
          );
        },
      );
      _throwIfCancelled(cancelToken);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.uploadDirectory,
          stage: FileTransferStage.extracting,
          title: title,
          detail: '正在远端解压目录...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          transferredBytes: totalBytes,
          totalBytes: totalBytes,
          compressed: true,
        ),
      );

      await _ensureRemoteDirectory(
        sshManager,
        _remoteDirname(remoteDirectoryPath),
      );
      _throwIfCancelled(cancelToken);
      await sshManager.executeCommand(
        'tar -xzf ${_shellQuote(remoteArchivePath)} -C ${_shellQuote(_remoteDirname(remoteDirectoryPath))}',
      );
      _throwIfCancelled(cancelToken);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.uploadDirectory,
          stage: FileTransferStage.cleaning,
          title: title,
          detail: '正在清理远端临时压缩包...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          transferredBytes: totalBytes,
          totalBytes: totalBytes,
          compressed: true,
        ),
      );

      await sshManager.executeCommand(
        'rm -f ${_shellQuote(remoteArchivePath)}',
      );
      _throwIfCancelled(cancelToken);
      await tempDir.delete(recursive: true);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.uploadDirectory,
          stage: FileTransferStage.completed,
          title: title,
          detail: '目录上传完成',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          transferredBytes: totalBytes,
          totalBytes: totalBytes,
          compressed: true,
          message: '目录已上传并自动解压',
        ),
      );
    } on TransferCancelledException catch (error) {
      await _safeDeleteDirectory(tempDir);
      await _safeDeleteRemoteFile(sshManager, remoteArchivePath);
      _emitCancelled(
        onProgress,
        FileTransferType.uploadDirectory,
        title,
        sourceLabel,
        targetLabel,
        error,
        compressed: true,
      );
      rethrow;
    } catch (error) {
      await _safeDeleteDirectory(tempDir);
      await _safeDeleteRemoteFile(sshManager, remoteArchivePath);
      _emitFailure(
        onProgress,
        FileTransferType.uploadDirectory,
        title,
        sourceLabel,
        targetLabel,
        error,
        compressed: true,
      );
      rethrow;
    }
  }

  Future<void> downloadDirectory({
    required SshManager sshManager,
    required String remoteDirectoryPath,
    required String localParentDirectory,
    void Function(FileTransferProgress progress)? onProgress,
    TransferCancellationToken? cancelToken,
  }) async {
    final title = '下载目录';
    final sourceLabel = remoteDirectoryPath;
    final targetLabel = localParentDirectory;
    final tempDir = await Directory.systemTemp.createTemp(
      'shellguard-download-',
    );
    final localArchivePath = p.join(
      tempDir.path,
      '${p.basename(remoteDirectoryPath)}-${DateTime.now().millisecondsSinceEpoch}.tar.gz',
    );
    final remoteArchivePath =
        '/tmp/shellguard-download-${DateTime.now().microsecondsSinceEpoch}.tar.gz';

    try {
      _throwIfCancelled(cancelToken);
      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.downloadDirectory,
          stage: FileTransferStage.preparing,
          title: title,
          detail: '正在远端打包目录...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          compressed: true,
        ),
      );

      await sshManager.executeCommand(
        'tar -czf ${_shellQuote(remoteArchivePath)} -C ${_shellQuote(_remoteDirname(remoteDirectoryPath))} ${_shellQuote(_remoteBasename(remoteDirectoryPath))}',
      );
      _throwIfCancelled(cancelToken);
      final totalBytes = await sshManager.statRemoteFileSize(remoteArchivePath);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.downloadDirectory,
          stage: FileTransferStage.transferring,
          title: title,
          detail: '正在下载压缩包...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          totalBytes: totalBytes,
          compressed: true,
        ),
      );

      await sshManager.downloadRemoteFile(
        remoteArchivePath,
        localArchivePath,
        cancelToken: cancelToken,
        onProgress: (bytes) {
          _emit(
            onProgress,
            FileTransferProgress(
              type: FileTransferType.downloadDirectory,
              stage: FileTransferStage.transferring,
              title: title,
              detail: '正在下载压缩包...',
              sourceLabel: sourceLabel,
              targetLabel: targetLabel,
              transferredBytes: bytes,
              totalBytes: totalBytes,
              compressed: true,
            ),
          );
        },
      );
      _throwIfCancelled(cancelToken);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.downloadDirectory,
          stage: FileTransferStage.extracting,
          title: title,
          detail: '正在本地解压目录...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          transferredBytes: totalBytes ?? 0,
          totalBytes: totalBytes,
          compressed: true,
        ),
      );

      await _extractTarArchive(localArchivePath, localParentDirectory);
      _throwIfCancelled(cancelToken);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.downloadDirectory,
          stage: FileTransferStage.cleaning,
          title: title,
          detail: '正在清理临时压缩包...',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          transferredBytes: totalBytes ?? 0,
          totalBytes: totalBytes,
          compressed: true,
        ),
      );

      await _safeDeleteRemoteFile(sshManager, remoteArchivePath);
      await _safeDeleteDirectory(tempDir);
      _throwIfCancelled(cancelToken);

      _emit(
        onProgress,
        FileTransferProgress(
          type: FileTransferType.downloadDirectory,
          stage: FileTransferStage.completed,
          title: title,
          detail: '目录下载完成',
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          transferredBytes: totalBytes ?? 0,
          totalBytes: totalBytes,
          compressed: true,
          message: '目录已下载并自动解压',
        ),
      );
    } on TransferCancelledException catch (error) {
      await _safeDeleteRemoteFile(sshManager, remoteArchivePath);
      await _safeDeleteDirectory(tempDir);
      _emitCancelled(
        onProgress,
        FileTransferType.downloadDirectory,
        title,
        sourceLabel,
        targetLabel,
        error,
        compressed: true,
      );
      rethrow;
    } catch (error) {
      await _safeDeleteRemoteFile(sshManager, remoteArchivePath);
      await _safeDeleteDirectory(tempDir);
      _emitFailure(
        onProgress,
        FileTransferType.downloadDirectory,
        title,
        sourceLabel,
        targetLabel,
        error,
        compressed: true,
      );
      rethrow;
    }
  }

  Future<void> _ensureRemoteDirectory(
    SshManager sshManager,
    String remoteDirectoryPath,
  ) async {
    await sshManager.executeCommand(
      'mkdir -p ${_shellQuote(remoteDirectoryPath)}',
    );
  }

  Future<void> _createTarArchive(
    String sourceDirectoryPath,
    String outputArchivePath,
  ) async {
    final sourceDirectory = Directory(sourceDirectoryPath);
    final parentDirectory = sourceDirectory.parent.path;
    final baseName = p.basename(sourceDirectoryPath);
    final result = await Process.run('tar', [
      '-czf',
      outputArchivePath,
      '-C',
      parentDirectory,
      baseName,
    ], runInShell: true);
    if (result.exitCode != 0) {
      throw Exception(
        '本地打包失败: ${(result.stderr as Object?)?.toString().trim()}',
      );
    }
  }

  Future<void> _extractTarArchive(
    String archivePath,
    String destinationDirectoryPath,
  ) async {
    await Directory(destinationDirectoryPath).create(recursive: true);
    final result = await Process.run('tar', [
      '-xzf',
      archivePath,
      '-C',
      destinationDirectoryPath,
    ], runInShell: true);
    if (result.exitCode != 0) {
      throw Exception(
        '本地解压失败: ${(result.stderr as Object?)?.toString().trim()}',
      );
    }
  }

  Future<void> _safeDeleteRemoteFile(
    SshManager sshManager,
    String remotePath,
  ) async {
    try {
      await sshManager.executeCommand('rm -f ${_shellQuote(remotePath)}');
    } catch (_) {}
  }

  Future<void> _safeDeleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _safeDeleteLocalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  void _emit(
    void Function(FileTransferProgress progress)? onProgress,
    FileTransferProgress progress,
  ) {
    onProgress?.call(progress);
  }

  void _emitCancelled(
    void Function(FileTransferProgress progress)? onProgress,
    FileTransferType type,
    String title,
    String sourceLabel,
    String targetLabel,
    Object error, {
    bool compressed = false,
  }) {
    _emit(
      onProgress,
      FileTransferProgress(
        type: type,
        stage: FileTransferStage.cancelled,
        title: title,
        detail: '传输已取消',
        sourceLabel: sourceLabel,
        targetLabel: targetLabel,
        compressed: compressed,
        message: _errorMessage(error),
      ),
    );
  }

  void _emitFailure(
    void Function(FileTransferProgress progress)? onProgress,
    FileTransferType type,
    String title,
    String sourceLabel,
    String targetLabel,
    Object error, {
    bool compressed = false,
  }) {
    _emit(
      onProgress,
      FileTransferProgress(
        type: type,
        stage: FileTransferStage.failed,
        title: title,
        detail: '传输失败',
        sourceLabel: sourceLabel,
        targetLabel: targetLabel,
        compressed: compressed,
        message: _errorMessage(error),
      ),
    );
  }

  String _errorMessage(Object error) {
    final raw = error.toString();
    return raw.startsWith('Exception: ') ? raw.substring(11) : raw;
  }

  void _throwIfCancelled(TransferCancellationToken? cancelToken) {
    if (cancelToken?.isCancelled ?? false) {
      throw const TransferCancelledException();
    }
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  String _remoteDirname(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty || normalized == '/') {
      return '/';
    }
    final segments = normalized.split('/')..removeLast();
    final joined = segments.where((item) => item.isNotEmpty).join('/');
    return joined.isEmpty ? '/' : '/$joined';
  }

  String _remoteBasename(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty || normalized == '/') {
      return '/';
    }
    final segments = normalized.split('/').where((item) => item.isNotEmpty);
    return segments.isEmpty ? '/' : segments.last;
  }
}
