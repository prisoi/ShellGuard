import 'dart:io';

import '../../models/share_listener_config.dart';

class ShareAuthDecision {
  final bool allowed;
  final int statusCode;
  final String message;

  const ShareAuthDecision._({
    required this.allowed,
    required this.statusCode,
    required this.message,
  });

  const ShareAuthDecision.allow()
      : this._(allowed: true, statusCode: HttpStatus.ok, message: 'ok');

  const ShareAuthDecision.deny({
    int statusCode = HttpStatus.unauthorized,
    String message = 'unauthorized',
  }) : this._(allowed: false, statusCode: statusCode, message: message);
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
