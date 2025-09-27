import 'package:flutter/material.dart';

/// Widget for exercise control buttons (play, pause, replay, metronome)
/// Handles the bottom control panel of the exercise screen
class ExerciseControls extends StatelessWidget {
  final bool isPlaying;
  final bool isPaused;
  final bool metronomeEnabled;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onReplay;
  final VoidCallback onMetronomeToggle;
  final VoidCallback onSettings;

  const ExerciseControls({
    super.key,
    required this.isPlaying,
    required this.isPaused,
    required this.metronomeEnabled,
    required this.onPlay,
    required this.onPause,
    required this.onReplay,
    required this.onMetronomeToggle,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Replay Button
          _buildControlButton(
            icon: Icons.replay,
            onPressed: onReplay,
            tooltip: 'Replay Exercise',
          ),
          
          // Main Play/Pause Button
          _buildControlButton(
            icon: isPlaying 
                ? Icons.pause 
                : isPaused 
                    ? Icons.play_arrow 
                    : Icons.play_arrow,
            onPressed: isPlaying ? onPause : onPlay,
            tooltip: isPlaying 
                ? 'Pause Exercise' 
                : isPaused 
                    ? 'Resume Exercise' 
                    : 'Start Exercise',
          ),
          
          // Metronome Toggle Button
          _buildMetronomeButton(),
        ],
      ),
    );
  }

  /// Build a standard control button
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Container(
      width: 50,
      height: 50,
      child: IconButton(
        icon: Icon(
          icon,
          size: 24,
          color: const Color(0xFF8B4511),
        ),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  /// Build the metronome toggle button with custom image
  Widget _buildMetronomeButton() {
    return Container(
      width: 50,
      height: 50,
      child: IconButton(
        icon: Image.asset(
          'assets/metronome.png',
          width: 24,
          height: 24,
          color: metronomeEnabled 
              ? Colors.blue 
              : const Color(0xFF8B4511),
        ),
        onPressed: onMetronomeToggle,
        tooltip: metronomeEnabled 
            ? 'Disable Metronome' 
            : 'Enable Metronome',
      ),
    );
  }
}