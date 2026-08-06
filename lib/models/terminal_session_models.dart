class TerminalSessionResult {
  final int? exitCode;
  final bool disconnected;

  const TerminalSessionResult({
    required this.exitCode,
    required this.disconnected,
  });
}

class TerminalSessionHandle {
  final String sessionId;
  final Stream<String> stream;
  final Future<TerminalSessionResult> done;
  final void Function(String data) write;
  final void Function(int columns, int rows, [int pixelWidth, int pixelHeight])
      resize;
  final Future<void> Function() close;

  const TerminalSessionHandle({
    required this.sessionId,
    required this.stream,
    required this.done,
    required this.write,
    required this.resize,
    required this.close,
  });
}
