import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';

/// Service responsible for metronome functionality
/// Handles metronome timing, audio playback, and visual feedback
class MetronomeService {
  // Audio player for metronome sounds
  late FlutterSoundPlayer _metronomePlayer;
  
  // Metronome state
  bool _isEnabled = false;
  bool _isFlashing = false;
  Timer? _metronomeTimer;
  
  // Timing variables
  int _lastWholeBeat = -1;
  int _lastClickStartUs = 0;
  static const int _clickDurationMs = 50;
  
  // Time signature
  int? _timeSigBeats;
  int? _timeSigBeatType;
  
  // Callbacks for UI updates
  Function(bool isFlashing)? onFlashUpdate;
  
  // Path to metronome sound
  final String _metronomeSound = 'assets/sounds/metronome sound.mp3';
  
  /// Initialize the metronome service
  MetronomeService() {
    _metronomePlayer = FlutterSoundPlayer();
  }
  
  /// Initialize the metronome player
  Future<void> initialize() async {
    try {
      await _metronomePlayer.openPlayer();
    } catch (e) {
      print('Error opening metronome player: $e');
    }
  }
  
  /// Set time signature for metronome beats
  void setTimeSignature(int beats, int beatType) {
    _timeSigBeats = beats;
    _timeSigBeatType = beatType;
  }
  
  /// Enable or disable the metronome
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled) {
      stop(immediate: true);
    }
  }
  
  /// Check if metronome is enabled
  bool get isEnabled => _isEnabled;
  
  /// Check if metronome is currently flashing
  bool get isFlashing => _isFlashing;
  
  /// Start metronome (called when exercise starts)
  void start() {
    _metronomeTimer?.cancel();
    _lastWholeBeat = -1;
  }
  
  /// Stop metronome
  void stop({bool immediate = false}) {
    _metronomeTimer?.cancel();
    _metronomeTimer = null;
    
    try {
      if (_metronomePlayer.isOpen() && _metronomePlayer.isPlaying) {
        if (immediate) {
          _metronomePlayer.stopPlayer();
        }
      }
    } catch (_) {}
    
    _setFlash(false);
  }
  
  /// Update metronome based on current playback time
  void updateTiming(double currentBeats, double metronomeBeatUnitSec, double lastMeasurePosition) {
    if (!_isEnabled) return;
    
    // Calculate target beat with look-ahead for audio latency compensation
    final double lookAheadSec = 0.03; // 30ms look-ahead
    final double adjustedCurrentBeats = currentBeats + (lookAheadSec / metronomeBeatUnitSec);
    final int targetBeat = adjustedCurrentBeats.floor();
    
    const double clickDurationSec = 0.05; // 50ms
    
    // Process any beats that need to be triggered
    while (_lastWholeBeat < targetBeat) {
      _lastWholeBeat++;
      final int beatsPerMeasure = (_timeSigBeats ?? 4).clamp(1, 12);
      final bool isDownbeat = (_lastWholeBeat % beatsPerMeasure) == 0;
      final double beatStartSec = _lastWholeBeat * metronomeBeatUnitSec;
      
      // Only trigger if we're still within the valid playback range
      if (beatStartSec + clickDurationSec <= lastMeasurePosition) {
        _triggerClick(downbeat: isDownbeat);
      } else {
        break;
      }
    }
  }
  
  /// Trigger a metronome click
  void _triggerClick({required bool downbeat}) {
    _playClick(downbeat: downbeat);
    
    // Update visual feedback
    _setFlash(true);
    
    // Schedule flash off
    Timer(const Duration(milliseconds: 100), () {
      _setFlash(false);
    });
  }
  
  /// Play metronome click sound
  void _playClick({bool downbeat = false}) {
    try {
      if (_metronomePlayer.isOpen()) {
        _metronomePlayer.startPlayer(
          fromURI: _metronomeSound,
          codec: Codec.mp3,
        );
        _lastClickStartUs = DateTime.now().microsecondsSinceEpoch;
      } else {
        // Fallback to system sound
        SystemSound.play(SystemSoundType.click);
        _lastClickStartUs = DateTime.now().microsecondsSinceEpoch;
      }
    } catch (e) {
      print('Error playing metronome click: $e');
      // Fallback to system sound on error
      SystemSound.play(SystemSoundType.click);
      _lastClickStartUs = DateTime.now().microsecondsSinceEpoch;
    }
  }
  
  /// Set flash state and notify UI
  void _setFlash(bool isFlashing) {
    _isFlashing = isFlashing;
    onFlashUpdate?.call(_isFlashing);
  }
  
  /// Reset metronome state
  void reset() {
    _lastWholeBeat = -1;
    _setFlash(false);
  }
  
  /// Dispose of resources
  Future<void> dispose() async {
    stop(immediate: true);
    await _metronomePlayer.closePlayer();
  }
}