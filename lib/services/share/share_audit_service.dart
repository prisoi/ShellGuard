import '../../models/remote_control_models.dart';
import '../storage_service.dart';

class ShareAuditService {
  final StorageService storageService;

  const ShareAuditService({
    required this.storageService,
  });

  Future<void> log({
    required RemoteAuditCategory category,
    required String action,
    required String summary,
    String detail = '',
    String sourceHost = '',
    String sourceLabel = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
    String sharedServerId = '',
    String sharedServerName = '',
    bool success = true,
    AccessTokenRecord? token,
  }) {
    return storageService.saveRemoteAuditLog(
      RemoteAuditRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        accessTokenId: token?.id,
        accessTokenNote: token?.note ?? '',
        category: category,
        action: action,
        summary: summary,
        detail: detail,
        sourceHost: sourceHost,
        sourceLabel: sourceLabel,
        sharedGroupId: sharedGroupId,
        sharedGroupName: sharedGroupName,
        sharedServerId: sharedServerId,
        sharedServerName: sharedServerName,
        success: success,
        createdAt: DateTime.now(),
      ),
    );
  }
}
