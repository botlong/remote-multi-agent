/// Gateway session model.
library;

enum GatewaySessionStatus {
  idle,
  running,
  waitingForApproval,
  error,
  completed,
  unknown;

  static GatewaySessionStatus from(String? raw) => switch (raw) {
        'idle' => GatewaySessionStatus.idle,
        'running' => GatewaySessionStatus.running,
        'waiting-for-approval' => GatewaySessionStatus.waitingForApproval,
        'error' => GatewaySessionStatus.error,
        'completed' => GatewaySessionStatus.completed,
        _ => GatewaySessionStatus.unknown,
      };

  String get wireName => switch (this) {
        GatewaySessionStatus.idle => 'idle',
        GatewaySessionStatus.running => 'running',
        GatewaySessionStatus.waitingForApproval => 'waiting-for-approval',
        GatewaySessionStatus.error => 'error',
        GatewaySessionStatus.completed => 'completed',
        GatewaySessionStatus.unknown => 'unknown',
      };
}

class GatewaySession {
  const GatewaySession({
    required this.id,
    required this.projectId,
    required this.directory,
    required this.agentId,
    required this.title,
    required this.status,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.raw,
    this.modelId,
  });

  final String id;
  final String projectId;
  final String directory;
  final String agentId;
  final String? modelId;
  final String title;
  final GatewaySessionStatus status;
  final int createdAtMs;
  final int updatedAtMs;
  final Map<String, dynamic> raw;

  factory GatewaySession.fromJson(Map<String, dynamic> json) {
    return GatewaySession(
      id: json['id'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      directory: json['directory'] as String? ?? '',
      agentId: json['agentId'] as String? ?? '',
      modelId: json['modelId'] as String?,
      title: json['title'] as String? ?? '',
      status: GatewaySessionStatus.from(json['status'] as String?),
      createdAtMs: _readInt(json['createdAt']) ?? 0,
      updatedAtMs: _readInt(json['updatedAt']) ?? 0,
      raw: Map<String, dynamic>.from(json),
    );
  }

  static int? _readInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
