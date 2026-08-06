import 'dart:io';

import '../../models/remote_control_models.dart';
import '../../models/share_listener_config.dart';
import '../storage_service.dart';

class ShareAuthDecision {
  final bool allowed;
  final int statusCode;
  final String message;
  final AccessTokenRecord? token;

  const ShareAuthDecision._({
    required this.allowed,
    required this.statusCode,
    required this.message,
    this.token,
  });

  const ShareAuthDecision.allow({
    AccessTokenRecord? token,
  }) : this._(
          allowed: true,
          statusCode: HttpStatus.ok,
          message: 'ok',
          token: token,
        );

  const ShareAuthDecision.deny({
    int statusCode = HttpStatus.unauthorized,
    String message = 'unauthorized',
  }) : this._(
          allowed: false,
          statusCode: statusCode,
          message: message,
        );
}

abstract class ShareAuthenticator {
  Future<ShareAuthDecision> authorize(
    HttpRequest request,
    ShareListenerConfig config,
  );
}

class AllowAllShareAuthenticator implements ShareAuthenticator {
  const AllowAllShareAuthenticator();

  @override
  Future<ShareAuthDecision> authorize(
    HttpRequest request,
    ShareListenerConfig config,
  ) async {
    return const ShareAuthDecision.allow();
  }
}

class TokenShareAuthenticator implements ShareAuthenticator {
  final StorageService storageService;

  const TokenShareAuthenticator({
    required this.storageService,
  });

  @override
  Future<ShareAuthDecision> authorize(
    HttpRequest request,
    ShareListenerConfig config,
  ) async {
    if (config.authMode == ShareAuthMode.none) {
      return const ShareAuthDecision.allow();
    }

    final rawHeader = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final tokenValue = rawHeader.startsWith('Bearer ')
        ? rawHeader.substring(7).trim()
        : '';
    if (tokenValue.isEmpty) {
      return const ShareAuthDecision.deny(
        statusCode: HttpStatus.unauthorized,
        message: '缺少 access-token',
      );
    }

    final token = await storageService.findAccessTokenByValue(tokenValue);
    if (token == null) {
      return const ShareAuthDecision.deny(
        statusCode: HttpStatus.unauthorized,
        message: 'access-token 不存在',
      );
    }
    if (token.isRevoked) {
      return const ShareAuthDecision.deny(
        statusCode: HttpStatus.unauthorized,
        message: 'access-token 已停用',
      );
    }
    if (token.isExpired) {
      return const ShareAuthDecision.deny(
        statusCode: HttpStatus.unauthorized,
        message: 'access-token 已过期',
      );
    }
    return ShareAuthDecision.allow(token: token);
  }
}
