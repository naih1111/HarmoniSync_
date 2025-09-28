import 'dart:async';
import 'package:metronome/metronome.dart';

/// Service responsible for metronome functionality
/// Handles metronome timing, audio playback, and visual feedback
class MetronomeService {
  // Metronome instance
  late Metronome _metronome;
  
  // Metronome state
  bool _isEnabled = false;
  bool _isFlashing = false;
  bool _isInitialized = false;
  bool _isPlaying = false;
  
  // Settings
  int _bpm = 120;
  int _volume = 50;
  int _timeSignature = 4;
  
  // Callbacks for UI updates
  Function(bool isFlashing)? onFlashUpdate;
  Function(int tick)? onTickUpdate;
  
  // Stream subscription for tick events
  StreamSubscription<int>? _tickSubscription;
  
  /// Initialize the metronome service
  MetronomeService();
  
  /// Initialize the metronome with audio files
  Future<void> initialize() async {
    try {
      // Create and initialize the metronome instance
      _metronome = Metronome();
      
      // Initialize with the WAV sound file path
      await _metronome.init(
        'assets/sounds/metronome_sound.wav',  // mainPath - use the WAV file
        bpm: _bpm,
        volume: _volume,
        enableTickCallback: true,
        timeSignature: _timeSignature,
        sampleRate: 44100,
      );
      
      _isInitialized = true;
      
      // Listen to tick events for visual feedback
      _tickSubscription = _metronome.tickStream.listen((int tick) {
        _triggerFlash();
        onTickUpdate?.call(tick);
      });
      
      print('Metronome initialized successfully');
      
    } catch (e) {
      print('Error initializing metronome: $e');
      _isInitialized = false;
      // Create a fallback metronome instance to prevent null reference
      _metronome = Metronome();
    }
  }
  
  /// Set time signature for metronome beats
  void setTimeSignature(int beats, int beatType) {
    _timeSignature = beats;
    if (_isInitialized) {
      _metronome.setTimeSignature(beats);
    }
  }
  
  /// Enable or disable the metronome
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled && _isPlaying) {
      stop(immediate: true);
    }
  }

  /// Play one measure of metronome based on time signature, then stop
  Future<void> playOneMeasure() async {
    if (!_isInitialized || !_isEnabled) {
      print('Cannot play one measure: initialized=$_isInitialized, enabled=$_isEnabled');
      return;
    }
    
    try {
      // Calculate duration for one measure in milliseconds
      // Duration = (beats per measure / BPM) * 60 * 1000
      double measureDurationMs = (_timeSignature / _bpm) * 60 * 1000;
      
      _metronome.play();
      _isPlaying = true;
      print('Playing one measure of metronome (${measureDurationMs.round()}ms)');
      
      // Wait for one measure to complete
      await Future.delayed(Duration(milliseconds: measureDurationMs.round()));
      
      // Stop after one measure
      stop(immediate: true);
      print('One measure completed, metronome stopped');
      
    } catch (e) {
      print('Error playing one measure: $e');
      _isPlaying = false;
    }
  }

  /// Start metronome for countdown (separate from exercise start)
  void startCountdown() {
    if (!_isInitialized || !_isEnabled) {
      print('Cannot start metronome countdown: initialized=$_isInitialized, enabled=$_isEnabled');
      return;
    }
    
    try {
      _metronome.play();
      _isPlaying = true;
      print('Metronome countdown started successfully');
    } catch (e) {
      print('Error starting metronome countdown: $e');
      _isPlaying = false;
    }
  }
  
  /// Set BPM (beats per minute)
  void setBPM(int bpm) {
    _bpm = bpm.clamp(30, 600);
    if (_isInitialized) {
      _metronome.setBPM(_bpm);
    }
  }
  
  /// Set volume (0-100)
  void setVolume(int volume) {
    _volume = volume.clamp(0, 100);
    if (_isInitialized) {
      _metronome.setVolume(_volume);
    }
  }
  
  /// Get current BPM
  int getBPM() => _bpm;
  
  /// Get current volume
  int getVolume() => _volume;
  
  /// Get current time signature
  int getTimeSignature() => _timeSignature;
  
  /// Check if metronome is enabled
  bool get isEnabled => _isEnabled;
  
  /// Check if metronome is currently flashing
  bool get isFlashing => _isFlashing;
  
  /// Check if metronome is initialized
  bool get isInitialized => _isInitialized;
  
  /// Check if metronome is playing
  bool get isPlaying => _isPlaying;
  
  /// Start metronome
  void start() {
    if (!_isInitialized || !_isEnabled) {
      print('Cannot start metronome: initialized=$_isInitialized, enabled=$_isEnabled');
      return;
    }
    
    try {
      _metronome.play();
      _isPlaying = true;
      print('Metronome started successfully');
    } catch (e) {
      print('Error starting metronome: $e');
      _isPlaying = false;
    }
  }
  
  /// Stop metronome
  void stop({bool immediate = false}) {
    if (!_isInitialized) {
      print('Cannot stop metronome: not initialized');
      return;
    }
    
    try {
      if (immediate) {
        _metronome.stop();
      } else {
        _metronome.pause();
      }
      _isPlaying = false;
      print('Metronome stopped successfully');
    } catch (e) {
      print('Error stopping metronome: $e');
    }
    
    _setFlash(false);
  }
  
  /// Pause metronome
  void pause() {
    if (!_isInitialized) {
      print('Cannot pause metronome: not initialized');
      return;
    }
    
    try {
      _metronome.pause();
      _isPlaying = false;
      print('Metronome paused successfully');
    } catch (e) {
      print('Error pausing metronome: $e');
    }
    
    _setFlash(false);
  }
  
  /// Resume metronome
  void resume() {
    if (!_isInitialized || !_isEnabled) {
      print('Cannot resume metronome: initialized=$_isInitialized, enabled=$_isEnabled');
      return;
    }
    
    try {
      _metronome.play();
      _isPlaying = true;
      print('Metronome resumed successfully');
    } catch (e) {
      print('Error resuming metronome: $e');
    }
  }
  
  /// This method is kept for compatibility with existing code
  /// but is no longer needed since the metronome package handles timing internally
  void updateTiming(double currentBeats, double metronomeBeatUnitSec, double lastMeasurePosition) {
    // The metronome package handles timing internally, so this method is now a no-op
    // Keeping it for backward compatibility
  }
  
  /// Trigger visual flash effect
  void _triggerFlash() {
    _setFlash(true);
    
    // Schedule flash off after 100ms
    Timer(const Duration(milliseconds: 100), () {
      _setFlash(false);
    });
  }
  
  /// Set flash state and notify UI
  void _setFlash(bool isFlashing) {
    _isFlashing = isFlashing;
    onFlashUpdate?.call(_isFlashing);
  }
  
  /// Reset metronome state
  void reset() {
    stop(immediate: true);
    _setFlash(false);
  }
  
  /// Dispose of resources
  Future<void> dispose() async {
    await _tickSubscription?.cancel();
    _tickSubscription = null;
    
    if (_isInitialized) {
      try {
        _metronome.destroy();
      } catch (e) {
        print('Error disposing metronome: $e');
      }
    }
    
    _isInitialized = false;
    _isPlaying = false;
  }
}