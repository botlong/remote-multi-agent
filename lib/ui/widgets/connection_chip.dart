import 'package:flutter/material.dart';

import '../../api/sse_stream.dart';

class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key, required this.state});
  final SseState state;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      SseState.connected =>
        ('Live', Colors.green, Icons.circle),
      SseState.connecting =>
        ('Connecting', Colors.orange, Icons.sync),
      SseState.disconnected =>
        ('Offline', Colors.red, Icons.cloud_off),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
