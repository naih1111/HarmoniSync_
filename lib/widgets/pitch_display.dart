import 'package:flutter/material.dart';

class PitchDisplay extends StatelessWidget {
  final double? pitch;

  const PitchDisplay({super.key, required this.pitch});

  @override
  Widget build(BuildContext context) {
    return Text(
      pitch != null
          ? "Detected Pitch: ${pitch!.toStringAsFixed(2)} Hz"
          : "No pitch detected",
      style: const TextStyle(fontSize: 24),
    );
  }
}
