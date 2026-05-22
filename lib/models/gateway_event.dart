/// Gateway event envelope decoded from SSE.
library;

import 'dart:convert';

class GatewayEvent {
  const GatewayEvent({
    required this.type,
    required this.sessionId,
    required this.agentId,
    required this.timestampMs,
    required this.data,
    required this.raw,
    required this.sseEvent,
  });

  final String type;
  final String sessionId;
  final String agentId;
  final int timestampMs;
  final Map<String, dynamic> data;
  final Map<String, dynamic> raw;
  final String sseEvent;

  factory GatewayEvent.fromJson(
    Map<String, dynamic> json, {
    String sseEvent = 'message',
  }) {
    final data = _readMap(json['data']);
    final raw = _readMap(json['raw'], fallback: json);
    return GatewayEvent(
      type: json['type'] as String? ?? sseEvent,
      sessionId: json['sessionId'] as String? ?? '',
      agentId: json['agentId'] as String? ?? '',
      timestampMs: _readInt(json['timestamp']) ?? 0,
      data: data,
      raw: raw,
      sseEvent: sseEvent,
    );
  }

  factory GatewayEvent.fromSseData({
    required String sseEvent,
    required String data,
  }) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return GatewayEvent.fromJson(decoded, sseEvent: sseEvent);
      }
      return GatewayEvent(
        type: sseEvent,
        sessionId: '',
        agentId: '',
        timestampMs: 0,
        data: <String, dynamic>{'_value': decoded},
        raw: <String, dynamic>{'_raw': decoded},
        sseEvent: sseEvent,
      );
    } catch (_) {
      return GatewayEvent(
        type: sseEvent,
        sessionId: '',
        agentId: '',
        timestampMs: 0,
        data: <String, dynamic>{'_raw': data},
        raw: <String, dynamic>{'_raw': data},
        sseEvent: sseEvent,
      );
    }
  }

  static int? _readInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Map<String, dynamic> _readMap(
    Object? value, {
    Map<String, dynamic> fallback = const <String, dynamic>{},
  }) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return Map<String, dynamic>.from(fallback);
  }
}
