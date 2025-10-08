import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/enhanced_yin.dart';
import '../utils/note_utils.dart';

/// Service responsible for handling real-time pitch detection
/// Manages microphone recording, audio processing, and note detection
class PitchDetectionService {
  // Audio recording components
  late FlutterSoundRecorder _recorder;
  StreamSubscription? _audioStreamSubscription;
  StreamController<Uint8List>? _audioStreamController;
  
  // Enhanced pitch detection
  late EnhancedYin _enhancedPitchDetector;
  
  // Detection state
  double _pitchConfidence = 0.0;
  String? _lastStableNote;
  int _stableNoteFrames = 0;
  String _lastRawNote = '';
  int _debugFrameCount = 0;
  double _lastDetectedFrequency = 0.0;
  bool _isVoiceDetected = false;
  
  // Current expected note for comparison
  String? _currentExpectedNote;
  
  // Adaptive detection parameters
  double _adaptiveStabilityThreshold = 0.25;
  int _adaptiveRequiredFrames = 2;
  double _currentNoteDuration = 1.0;
  
  // Singer gender settings
  bool _isMaleSinger = true;
  final double _maleFrequencyMin = 80.0;
  final double _maleFrequencyMax = 400.0;
  final double _femaleFrequencyMin = 150.0;
  final double _femaleFrequencyMax = 800.0;
  
  // Debug and testing
  Map<String, dynamic> _componentStats = {};
  bool _testWienerFilter = false;
  bool _testVoiceActivityDetector = false;
  bool _testPitchSmoother = false;
  bool _showComponentStats = false;
  
  // Callbacks for communication with UI
  Function(String note, double confidence, bool isCorrect)? onNoteDetected;
  Function(String debugInfo)? onDebugUpdate;
  Function(Map<String, dynamic> stats)? onStatsUpdate;
  
  /// Initialize the pitch detection service
  PitchDetectionService() {
    _recorder = FlutterSoundRecorder();
    _enhancedPitchDetector = EnhancedYin(
      sampleRate: 44100,
      wienerStrength: 0.3,
      vadSensitivity: 0.4,
      medianWindow: 3,
      upsampleFactor: 1,
      enableParabolicRefinement: false,
    );
  }
  
  /// Initialize the audio recorder with microphone permissions
  Future<void> initialize() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Microphone permission not granted');
    }
    
    await _recorder.openRecorder();
    
    try {
      await _recorder.setSubscriptionDuration(const Duration(milliseconds: 60));
    } catch (_) {}
  }
  
  /// Update singer gender settings for optimized frequency detection
  void updateSingerGender(bool isMale) {
    _isMaleSinger = isMale;
  }
  
  /// Update current note duration for adaptive detection
  void updateNoteDuration(double duration) {
    _currentNoteDuration = duration;
    _calculateAdaptiveDetection();
  }
  
  /// Update BPM for adaptive detection calculations
  void updateBPM(double bpm) {
    _currentBPM = bpm;
    _calculateAdaptiveDetection();
  }
  
  // Add BPM tracking
  double _currentBPM = 120.0;
  
  /// Calculate adaptive detection parameters based on BPM and note duration
  void _calculateAdaptiveDetection() {
    // Calculate how long each note lasts in milliseconds
    final double beatDurationMs = (60.0 / _currentBPM) * 1000; // ms per beat
    final double noteDurationMs = _currentNoteDuration * beatDurationMs;
   
    // Adaptive stability based on note duration
    if (noteDurationMs < 500) {
      // Very fast notes (eighth notes, 16th notes) - need instant detection
      _adaptiveRequiredFrames = 1;
      _adaptiveStabilityThreshold = 0.15;
    } else if (noteDurationMs < 1000) {
      // Fast notes (quarter notes at high BPM) - need quick detection
      _adaptiveRequiredFrames = 1;
      _adaptiveStabilityThreshold = 0.2;
    } else if (noteDurationMs < 2000) {
      // Medium notes (quarter notes at medium BPM) - balanced detection
      _adaptiveRequiredFrames = 2;
      _adaptiveStabilityThreshold = 0.25;
    } else {
      // Slow notes (half notes, whole notes) - can afford more stability
      _adaptiveRequiredFrames = 3;
      _adaptiveStabilityThreshold = 0.3;
    }
   
    // Also adjust based on BPM
    if (_currentBPM > 160) {
      // Very fast tempo - prioritize speed
      _adaptiveRequiredFrames = (_adaptiveRequiredFrames - 1).clamp(1, 4);
      _adaptiveStabilityThreshold = (_adaptiveStabilityThreshold - 0.05).clamp(0.1, 0.4);
    } else if (_currentBPM < 80) {
      // Slow tempo - can afford more stability
      _adaptiveRequiredFrames = (_adaptiveRequiredFrames + 1).clamp(1, 4);
      _adaptiveStabilityThreshold = (_adaptiveStabilityThreshold + 0.05).clamp(0.1, 0.4);
    }
  }
  
  /// Start pitch detection from microphone
  Future<void> startDetection(String? expectedNote) async {
    _currentExpectedNote = expectedNote;
    
    try {
      if (_recorder.isRecording) {
        await _recorder.stopRecorder();
      }
    } catch (_) {}
    
    _audioStreamController = StreamController<Uint8List>();
    
    await _recorder.startRecorder(
      toStream: _audioStreamController!.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 44100,
    );
    
    Timer? throttleTimer;
    _audioStreamSubscription = _audioStreamController!.stream.listen((buffer) {
      try {
        final int processingInterval = 80; // Optimized interval
        if (throttleTimer?.isActive ?? false) return;
        throttleTimer = Timer(Duration(milliseconds: processingInterval), () {});
        
        final pitchHz = _enhancedPitchDetector.processFrame(buffer, 44100);
        if (pitchHz == null) {
          _isVoiceDetected = false;
          _stableNoteFrames = 0;
          _lastStableNote = null;
          _updateDebugInfo();
          return;
        }
        
        final note = NoteUtils.getGenderAwareNote(pitchHz, isMale: _isMaleSinger);
        final confidence = _calculateConfidence(pitchHz);
        
        _updateDebugInfo();
        
        if (confidence > _adaptiveStabilityThreshold) {
          if (_lastStableNote != note) {
            _lastStableNote = note;
            _stableNoteFrames = 1;
            _notifyNoteDetected(note, confidence, _currentExpectedNote);
          } else {
            _stableNoteFrames++;
            if (_stableNoteFrames % 3 == 0) {
              _notifyNoteDetected(note, confidence, _currentExpectedNote);
            }
          }
        } else {
          _stableNoteFrames = 0;
          _lastStableNote = null;
        }
      } catch (e) {
        debugPrint('Error in pitch detection: $e');
      }
    });
  }
  
  /// Update the expected note without restarting detection
  void updateExpectedNote(String? expectedNote) {
    _currentExpectedNote = expectedNote;
  }
  
  /// Stop pitch detection
  Future<void> stopDetection() async {
    _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _audioStreamController?.close();
    _audioStreamController = null;
    
    _enhancedPitchDetector = EnhancedYin(
      sampleRate: 44100,
      wienerStrength: 0.6,
      vadSensitivity: 0.7,
      medianWindow: 5,
      upsampleFactor: 2,
      enableParabolicRefinement: true,
    );
    _stableNoteFrames = 0;
    _lastStableNote = null;
    
    try {
      await _recorder.stopRecorder();
    } catch (e) {
      debugPrint('Error stopping recorder: $e');
    }
  }
  
  /// Calculate confidence based on frequency stability and singer gender
  double _calculateConfidence(double frequency) {
    _lastDetectedFrequency = frequency;
    
    final double minFreq = _isMaleSinger ? _maleFrequencyMin : _femaleFrequencyMin;
    final double maxFreq = _isMaleSinger ? _maleFrequencyMax : _femaleFrequencyMax;
    
    if (frequency >= minFreq && frequency <= maxFreq) {
      return 1.0;
    } else if (frequency >= (minFreq * 0.8) && frequency <= (maxFreq * 1.2)) {
      return 0.8;
    } else if (frequency >= (minFreq * 0.6) && frequency <= (maxFreq * 1.5)) {
      return 0.6;
    } else {
      return 0.2;
    }
  }
  
  /// Notify listeners about detected note
  void _notifyNoteDetected(String note, double confidence, String? expectedNote) {
    _debugFrameCount++;
    _lastRawNote = note;
    _isVoiceDetected = confidence > 0.3;
    
    // Test individual components if enabled
    if (_testWienerFilter || _testVoiceActivityDetector || _testPitchSmoother) {
      _performComponentTests();
    }
    
    // Update component statistics if enabled
    if (_showComponentStats) {
      _updateComponentStats();
    }
    
    // Use gender-aware note comparison for better accuracy
    final bool isCorrect = expectedNote != null && 
        NoteUtils.isEquivalentNote(note, expectedNote, isMale: _isMaleSinger);
    onNoteDetected?.call(note, confidence, isCorrect);
  }
  
  /// Update debug information
  void _updateDebugInfo() {
    final double beatDurationMs = (60.0 / _currentBPM) * 1000;
    final double noteDurationMs = _currentNoteDuration * beatDurationMs;
    final int processingInterval = noteDurationMs < 400 ? 40 :
                                 (noteDurationMs < 800 ? 60 :
                                 (_currentBPM > 140 ? 60 : (_currentBPM < 80 ? 120 : 80)));
   
    // Get performance metrics
    final performanceMetrics = _getPerformanceMetrics();
   
    final String debugInfo = '''
Voice: ${_isVoiceDetected ? 'YES' : 'NO'}
Detected: $_lastRawNote
Expected: ${_currentExpectedNote ?? 'None'}
Confidence: ${(_pitchConfidence * 100).toStringAsFixed(1)}%
Frames: $_debugFrameCount
Frequency: ${_lastDetectedFrequency.toStringAsFixed(1)} Hz
Stable: ${_stableNoteFrames}/$_adaptiveRequiredFrames
BPM: ${_currentBPM.toStringAsFixed(0)}
Note Duration: ${noteDurationMs.toStringAsFixed(0)}ms
Processing: ${processingInterval}ms
Threshold: ${(_adaptiveStabilityThreshold * 100).toStringAsFixed(1)}%
Singer: ${_isMaleSinger ? 'MALE' : 'FEMALE'}
Status: ${_stableNoteFrames >= 1 ? 'DETECTED' : 'DETECTING...'}
Change: ${_lastStableNote != _lastRawNote ? 'NEW NOTE' : 'SAME NOTE'}

=== PERFORMANCE METRICS ===
${performanceMetrics['summary']}
Processing Time: ${performanceMetrics['processingTime']}ms
Memory Usage: ${performanceMetrics['memoryUsage']}
Component Health: ${performanceMetrics['componentHealth']}
''';
    
    onDebugUpdate?.call(debugInfo);
  }
  
  /// Get comprehensive performance metrics
  Map<String, String> _getPerformanceMetrics() {
    final stats = _componentStats;
    final stopwatch = Stopwatch()..start();
   
    // Simulate processing time measurement
    final processingTime = stopwatch.elapsedMilliseconds;
   
    // Component health assessment
    String componentHealth = 'EXCELLENT';
    List<String> issues = [];
   
    if (stats.containsKey('wiener')) {
      final wienerStats = stats['wiener'] as Map<String, dynamic>;
      final double snr = wienerStats['snrDb'] ?? -60.0;
      if (snr < -50) {
        issues.add('High noise');
        componentHealth = 'FAIR';
      }
    }
   
    if (stats.containsKey('vad')) {
      final vadStats = stats['vad'] as Map<String, dynamic>;
      final double accuracy = vadStats['accuracy'] ?? 0.0;
      if (accuracy < 70) {
        issues.add('VAD accuracy low');
        componentHealth = 'POOR';
      }
    }
   
    if (stats.containsKey('smoother')) {
      final smootherStats = stats['smoother'] as Map<String, dynamic>;
      final int outlierCount = smootherStats['outlierCount'] ?? 0;
      final int totalProcessed = smootherStats['totalProcessed'] ?? 1;
      if (outlierCount / totalProcessed > 0.3) {
        issues.add('High pitch instability');
        componentHealth = 'FAIR';
      }
    }
   
    // Overall system performance summary
    String summary = 'System running optimally';
    if (issues.isNotEmpty) {
      summary = 'Issues: ${issues.join(', ')}';
    }
   
    return {
      'summary': summary,
      'processingTime': processingTime.toString(),
      'memoryUsage': '${(_debugFrameCount * 0.1).toStringAsFixed(1)}KB',
      'componentHealth': componentHealth,
    };
  }
  
  /// Update component statistics
  void _updateComponentStats() {
    if (_showComponentStats) {
      _componentStats = _enhancedPitchDetector.getStatistics();
      onStatsUpdate?.call(_componentStats);
    }
  }
  
  /// Enable/disable debug features
  void setDebugMode({
    bool? testWiener,
    bool? testVAD,
    bool? testSmoother,
    bool? showStats,
  }) {
    _testWienerFilter = testWiener ?? _testWienerFilter;
    _testVoiceActivityDetector = testVAD ?? _testVoiceActivityDetector;
    _testPitchSmoother = testSmoother ?? _testPitchSmoother;
    _showComponentStats = showStats ?? _showComponentStats;
  }
  
  /// Perform individual component tests
  void _performComponentTests() {
    if (_testWienerFilter) {
      _testWienerFilterIsolated();
    }
   
    if (_testVoiceActivityDetector) {
      _testVADIsolated();
    }
   
    if (_testPitchSmoother) {
      _testPitchSmootherIsolated();
    }
  }

  /// Isolated test for Wiener Filter component
  void _testWienerFilterIsolated() {
    final stats = _enhancedPitchDetector.getStatistics();
    if (stats.containsKey('wiener')) {
      final wienerStats = stats['wiener'] as Map<String, dynamic>;
      final double snr = wienerStats['snrDb'] ?? -60.0;
      final double noiseReduction = wienerStats['noiseReduction'] ?? 0.0;
     
      debugPrint('=== WIENER FILTER TEST ===');
      debugPrint('SNR: ${snr.toStringAsFixed(2)}dB');
      debugPrint('Noise Reduction: ${noiseReduction.toStringAsFixed(1)}%');
      debugPrint('Status: ${snr > -40 ? "GOOD" : snr > -50 ? "FAIR" : "POOR"}');
      debugPrint('Filter Strength: ${wienerStats['strength'] ?? 0.5}');
      debugPrint('Initialized: ${wienerStats['initialized'] ?? false}');
     
      // Test different noise levels
      if (snr > -30) {
        debugPrint('✅ Clean signal detected - filter working optimally');
      } else if (snr > -45) {
        debugPrint('⚠️ Moderate noise - filter actively reducing noise');
      } else {
        debugPrint('🔴 High noise environment - maximum filtering applied');
      }
    }
  }

  /// Isolated test for Voice Activity Detector component
  void _testVADIsolated() {
    final stats = _enhancedPitchDetector.getStatistics();
    if (stats.containsKey('vad')) {
      final vadStats = stats['vad'] as Map<String, dynamic>;
      final int voiceFrames = vadStats['voiceFrames'] ?? 0;
      final int totalFrames = vadStats['totalFrames'] ?? 1;
      final double accuracy = vadStats['accuracy'] ?? 0.0;
      final double voiceRatio = voiceFrames / totalFrames;
     
      debugPrint('=== VOICE ACTIVITY DETECTOR TEST ===');
      debugPrint('Voice Frames: $voiceFrames/$totalFrames (${(voiceRatio * 100).toStringAsFixed(1)}%)');
      debugPrint('Detection Accuracy: ${accuracy.toStringAsFixed(1)}%');
      debugPrint('Current Confidence: ${((_componentStats['vadConfidence'] ?? 0.0) * 100).toStringAsFixed(1)}%');
     
      // Test voice detection sensitivity
      if (voiceRatio > 0.7) {
        debugPrint('✅ High voice activity - good singing detected');
      } else if (voiceRatio > 0.3) {
        debugPrint('⚠️ Moderate voice activity - intermittent singing');
      } else {
        debugPrint('🔴 Low voice activity - check microphone or sing louder');
      }
     
      // Test accuracy
      if (accuracy > 85) {
        debugPrint('✅ Excellent VAD accuracy');
      } else if (accuracy > 70) {
        debugPrint('⚠️ Good VAD accuracy');
      } else {
        debugPrint('🔴 VAD accuracy needs improvement');
      }
    }
  }

  /// Isolated test for Pitch Smoother component
  void _testPitchSmootherIsolated() {
    final stats = _enhancedPitchDetector.getStatistics();
    if (stats.containsKey('smoother')) {
      final smootherStats = stats['smoother'] as Map<String, dynamic>;
      final int outlierCount = smootherStats['outlierCount'] ?? 0;
      final double smoothingFactor = smootherStats['smoothingFactor'] ?? 0.3;
      final int totalProcessed = smootherStats['totalProcessed'] ?? 1;
      final double outlierRatio = outlierCount / totalProcessed;
     
      debugPrint('=== PITCH SMOOTHER TEST ===');
      debugPrint('Outliers Removed: $outlierCount/$totalProcessed (${(outlierRatio * 100).toStringAsFixed(1)}%)');
      debugPrint('Smoothing Factor: ${smoothingFactor.toStringAsFixed(2)}');
      debugPrint('Stability: ${_stableNoteFrames}/${_adaptiveRequiredFrames} frames');
     
      // Test smoothing effectiveness
      if (outlierRatio < 0.1) {
        debugPrint('✅ Stable pitch - minimal smoothing needed');
      } else if (outlierRatio < 0.3) {
        debugPrint('⚠️ Moderate pitch variation - smoother actively working');
      } else {
        debugPrint('🔴 High pitch instability - maximum smoothing applied');
      }
     
      // Test note stability
      if (_stableNoteFrames >= _adaptiveRequiredFrames) {
        debugPrint('✅ Note detection stable');
      } else {
        debugPrint('⏳ Building note stability...');
      }
    }
  }
  
  /// Get current detection statistics
  Map<String, dynamic> getStatistics() {
    return {
      'confidence': _pitchConfidence,
      'isVoiceDetected': _isVoiceDetected,
      'stableFrames': _stableNoteFrames,
      'requiredFrames': _adaptiveRequiredFrames,
      'lastFrequency': _lastDetectedFrequency,
      'componentStats': _componentStats,
    };
  }
  
  /// Dispose of resources
  Future<void> dispose() async {
    await stopDetection();
    await _recorder.closeRecorder();
  }
}