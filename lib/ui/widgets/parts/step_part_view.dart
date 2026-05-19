import 'package:flutter/material.dart';

/// Step parts in the OpenCode protocol mark the boundary between agent
/// "rounds" inside a single message (think of them like sub-paragraphs).
/// They carry no content — historically we drew a divider, but it added
/// visual noise that looked like a stalled progress bar. We render nothing.
class StepPartView extends StatelessWidget {
  const StepPartView({super.key, required this.start});
  final bool start;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
