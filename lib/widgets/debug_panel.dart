import 'package:flutter/material.dart';

/// Debug panel widget for development and testing features
/// Displays pitch detection information and component statistics
class DebugPanel extends StatelessWidget {
  final bool isVisible;
  final String debugInfo;
  final Map<String, dynamic> componentStats;
  final bool testWienerFilter;
  final bool testVoiceActivityDetector;
  final bool testPitchSmoother;
  final bool showComponentStats;
  final String? currentDetectedNote;
  final String? expectedNote;
  final double pitchConfidence;
  final bool isVoiceDetected;

  const DebugPanel({
    super.key,
    required this.isVisible,
    required this.debugInfo,
    required this.componentStats,
    required this.testWienerFilter,
    required this.testVoiceActivityDetector,
    required this.testPitchSmoother,
    required this.showComponentStats,
    this.currentDetectedNote,
    this.expectedNote,
    required this.pitchConfidence,
    required this.isVoiceDetected,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Positioned(
      top: 50,
      left: 16,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildTestModeIndicators(),
            _buildComponentStats(),
            _buildBasicInfo(),
            if (showComponentStats && componentStats.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildPerformanceMetrics(),
            ],
          ],
        ),
      ),
    );
  }

  /// Build the debug panel header
  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          isVoiceDetected ? Icons.mic : Icons.mic_off,
          color: isVoiceDetected ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        const Text(
          'Debug Panel',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  /// Build test mode indicators
  Widget _buildTestModeIndicators() {
    List<Widget> indicators = [];
    
    if (testWienerFilter) {
      indicators.add(const Text(
        '🔧 Wiener Filter Test Mode',
        style: TextStyle(color: Colors.green, fontSize: 12),
      ));
    }
    
    if (testVoiceActivityDetector) {
      indicators.add(const Text(
        '🎤 VAD Test Mode',
        style: TextStyle(color: Colors.orange, fontSize: 12),
      ));
    }
    
    if (testPitchSmoother) {
      indicators.add(const Text(
        '🎵 Pitch Smoother Test Mode',
        style: TextStyle(color: Colors.purple, fontSize: 12),
      ));
    }

    if (indicators.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...indicators,
          const SizedBox(height: 4),
        ],
      );
    }
    
    return const SizedBox.shrink();
  }

  /// Build component statistics widgets
  Widget _buildComponentStats() {
    if (!showComponentStats || componentStats.isEmpty) {
      return const SizedBox.shrink();
    }

    List<Widget> widgets = [];
    
    if (componentStats.containsKey('wiener')) {
      final wienerStats = componentStats['wiener'] as Map<String, dynamic>;
      widgets.add(Text(
        'Wiener: SNR ${wienerStats['snrDb']?.toStringAsFixed(1) ?? "N/A"}dB',
        style: const TextStyle(color: Colors.green, fontSize: 10),
      ));
    }
    
    if (componentStats.containsKey('vad')) {
      final vadStats = componentStats['vad'] as Map<String, dynamic>;
      widgets.add(Text(
        'VAD: ${vadStats['voiceFrames'] ?? 0}/${vadStats['totalFrames'] ?? 0} frames',
        style: const TextStyle(color: Colors.orange, fontSize: 10),
      ));
    }
    
    if (componentStats.containsKey('smoother')) {
      final smootherStats = componentStats['smoother'] as Map<String, dynamic>;
      widgets.add(Text(
        'Smoother: ${smootherStats['outlierCount'] ?? 0} outliers',
        style: const TextStyle(color: Colors.purple, fontSize: 10),
      ));
    }

    if (widgets.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 Component Statistics:',
            style: TextStyle(color: Colors.cyan, fontSize: 12),
          ),
          const SizedBox(height: 4),
          ...widgets,
          const SizedBox(height: 4),
        ],
      );
    }
    
    return const SizedBox.shrink();
  }

  /// Build basic detection information
  Widget _buildBasicInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detected: ${currentDetectedNote ?? "None"}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        Text(
          'Expected: ${expectedNote ?? "None"}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        Text(
          'Confidence: ${(pitchConfidence * 100).toStringAsFixed(1)}%',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        Text(
          'Voice: ${isVoiceDetected ? "Yes" : "No"}',
          style: TextStyle(
            color: isVoiceDetected ? Colors.green : Colors.red,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// Build performance metrics section
  Widget _buildPerformanceMetrics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildPerformanceIndicator('CPU', _getProcessingLoad(), Colors.blue),
            _buildPerformanceIndicator('MEM', _getMemoryUsage(), Colors.green),
            _buildPerformanceIndicator('HEALTH', _getSystemHealth(), _getHealthColor()),
          ],
        ),
      ],
    );
  }

  /// Build individual performance indicator
  Widget _buildPerformanceIndicator(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 9),
        ),
      ],
    );
  }

  /// Get processing load estimate
  String _getProcessingLoad() {
    // Simplified processing load calculation
    final double load = pitchConfidence * 100;
    return '${load.toStringAsFixed(0)}%';
  }

  /// Get memory usage estimate
  String _getMemoryUsage() {
    // Simplified memory usage estimate
    return '2.5MB';
  }

  /// Get system health status
  String _getSystemHealth() {
    int healthScore = 100;
    
    if (componentStats.containsKey('wiener')) {
      final wienerStats = componentStats['wiener'] as Map<String, dynamic>;
      final double snr = wienerStats['snrDb'] ?? -60.0;
      if (snr < -30) healthScore -= 15;
    }
    
    if (componentStats.containsKey('vad')) {
      final vadStats = componentStats['vad'] as Map<String, dynamic>;
      final double accuracy = vadStats['accuracy'] ?? 0.0;
      if (accuracy < 60) healthScore -= 20;
    }
    
    return '${healthScore.clamp(0, 100)}%';
  }

  /// Get health indicator color
  Color _getHealthColor() {
    final String health = _getSystemHealth();
    final int healthValue = int.tryParse(health.replaceAll('%', '')) ?? 0;
    
    if (healthValue >= 80) return Colors.green;
    if (healthValue >= 60) return Colors.orange;
    return Colors.red;
  }
}