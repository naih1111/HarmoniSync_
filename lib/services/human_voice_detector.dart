import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'voice_activity_detector.dart';
import 'enhanced_yin.dart';
import 'pitch_smoother.dart';

/// Detection result structure
class VoiceDetectionResult {
  final String status;
  final String type;
  final String? gender;
  final double? confidence;
  final String? message;
  final double? pitch;
  final bool? isHumming;

  VoiceDetectionResult({
    required this.status,
    required this.type,
    this.gender,
    this.confidence,
    this.message,
    this.pitch,
    this.isHumming,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {
      'status': status,
      'type': type,
    };
    
    if (gender != null) result['gender'] = gender;
    if (confidence != null) result['confidence'] = confidence;
    if (message != null) result['message'] = message;
    if (pitch != null) result['pitch'] = pitch;
    if (isHumming != null) result['isHumming'] = isHumming;
    
    return result;
  }
}

/// Temporal buffer for smoothing outputs
class _TemporalBuffer {
  final int maxSize;
  final List<bool> _vadHistory = [];
  final List<double?> _pitchHistory = [];
  final List<DateTime> _timestamps = [];
  final List<double> _amplitudeHistory = []; // New: amplitude tracking
  
  _TemporalBuffer({required this.maxSize});
  
  void addFrame(bool vadResult, double? pitch, [double? amplitude]) {
    final now = DateTime.now();
    
    _vadHistory.add(vadResult);
    _pitchHistory.add(pitch);
    _timestamps.add(now);
    _amplitudeHistory.add(amplitude ?? 0.0);
    
    // Remove old entries beyond buffer size
    while (_vadHistory.length > maxSize) {
      _vadHistory.removeAt(0);
      _pitchHistory.removeAt(0);
      _timestamps.removeAt(0);
      _amplitudeHistory.removeAt(0);
    }
  }
  
  /// Get smoothed VAD result over time window
  bool getSmoothedVAD(Duration timeWindow) {
    if (_vadHistory.isEmpty) return false;
    
    final cutoffTime = DateTime.now().subtract(timeWindow);
    int validCount = 0;
    int totalCount = 0;
    
    for (int i = _timestamps.length - 1; i >= 0; i--) {
      if (_timestamps[i].isBefore(cutoffTime)) break;
      if (_vadHistory[i]) validCount++;
      totalCount++;
    }
    
    // Require majority of recent frames to indicate voice activity
    return totalCount > 0 && (validCount / totalCount) > 0.6;
  }
  
  /// Get recent pitch values within time window
  List<double> getRecentPitches(Duration timeWindow) {
    final cutoffTime = DateTime.now().subtract(timeWindow);
    final List<double> recentPitches = [];
    
    for (int i = _timestamps.length - 1; i >= 0; i--) {
      if (_timestamps[i].isBefore(cutoffTime)) break;
      if (_pitchHistory[i] != null) {
        recentPitches.add(_pitchHistory[i]!);
      }
    }
    
    return recentPitches.reversed.toList();
  }
  
  /// NEW: Calculate pitch stability (variance) over time window
  double getPitchStability(Duration timeWindow) {
    final recentPitches = getRecentPitches(timeWindow);
    if (recentPitches.length < 3) return 0.0; // Not enough data
    
    // Calculate variance
    final mean = recentPitches.reduce((a, b) => a + b) / recentPitches.length;
    final variance = recentPitches
        .map((pitch) => (pitch - mean) * (pitch - mean))
        .reduce((a, b) => a + b) / recentPitches.length;
    
    // Return stability score (lower variance = higher stability)
    // Normalize to 0-1 range where 1 = very stable
    return 1.0 / (1.0 + variance / 100.0); // Adjust divisor as needed
  }
  
  /// NEW: Get duration of current continuous voiced segment
  Duration getCurrentVoicedDuration() {
    if (_vadHistory.isEmpty || !_vadHistory.last) return Duration.zero;
    
    // Find the start of current voiced segment
    int startIndex = _vadHistory.length - 1;
    for (int i = _vadHistory.length - 1; i >= 0; i--) {
      if (!_vadHistory[i]) {
        startIndex = i + 1;
        break;
      }
      if (i == 0) startIndex = 0; // Entire buffer is voiced
    }
    
    if (startIndex >= _timestamps.length) return Duration.zero;
    return DateTime.now().difference(_timestamps[startIndex]);
  }
  
  /// NEW: Check for amplitude spikes (sudden volume changes)
  bool hasAmplitudeSpike(Duration timeWindow, double spikeThreshold) {
    final cutoffTime = DateTime.now().subtract(timeWindow);
    final List<double> recentAmplitudes = [];
    
    for (int i = _timestamps.length - 1; i >= 0; i--) {
      if (_timestamps[i].isBefore(cutoffTime)) break;
      recentAmplitudes.add(_amplitudeHistory[i]);
    }
    
    if (recentAmplitudes.length < 3) return false;
    
    final mean = recentAmplitudes.reduce((a, b) => a + b) / recentAmplitudes.length;
    final maxAmplitude = recentAmplitudes.reduce((a, b) => a > b ? a : b);
    
    // Check if recent max is significantly higher than average
    return (maxAmplitude - mean) > spikeThreshold;
  }
  
  /// Check if there's been a recent gap in pitch detection
  Duration getTimeSinceLastValidPitch() {
    for (int i = _pitchHistory.length - 1; i >= 0; i--) {
      if (_pitchHistory[i] != null) {
        return DateTime.now().difference(_timestamps[i]);
      }
    }
    return Duration(seconds: 10); // Large value if no valid pitch found
  }
}

/// Enhanced Human Voice Detector with robust humming detection
class HumanVoiceDetector {
  // Existing HarmoniSync components
  late VoiceActivityDetector _vad;
  late EnhancedYin _yin;
  late PitchSmoother _pitchSmoother;
  
  // Temporal smoothing
  late _TemporalBuffer _temporalBuffer;
  
  // Audio processing parameters
  static const int sampleRate = 16000;
  static const int frameSize = 1024;
  static const double genderThreshold = 180.0; // Hz
  
  // Enhanced robust humming detection parameters
  static const Duration smoothingWindow = Duration(milliseconds: 250); // 200-300ms window
  static const Duration gapTolerance = Duration(milliseconds: 80); // <100ms gap tolerance
  static const double minHummingFreq = 80.0; // Hz - minimum humming frequency  
  static const double maxHummingFreq = 300.0; // Hz - maximum humming frequency (updated to spec)
  static const Duration minHummingDuration = Duration(milliseconds: 400); // 0.3-0.5s minimum duration
  static const double minPitchStability = 0.7; // Minimum stability score (0-1)
  static const double amplitudeSpikeThreshold = 0.3; // Threshold for amplitude spike detection
  static const int bufferFrames = 20; // ~250ms at 80fps
  
  // State tracking
  bool _isInitialized = false;
  bool _isCurrentlyHumming = false;
  DateTime? _hummingStartTime; // NEW: Track when humming started
  StreamController<VoiceDetectionResult>? _resultController;
  
  /// Initialize the detector
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize existing HarmoniSync components with tuned parameters
      _vad = VoiceActivityDetector(sampleRate: sampleRate);
      _yin = EnhancedYin(sampleRate: sampleRate);
      
      // Initialize pitch smoother with more lenient settings for humming
      _pitchSmoother = PitchSmoother(
        windowSize: 7, // Slightly larger window for stability
        outlierThreshold: 5.0, // More lenient threshold
        useWeightedMedian: true,
      );
      
      // Initialize temporal buffer
      _temporalBuffer = _TemporalBuffer(maxSize: bufferFrames);
      
      _resultController = StreamController<VoiceDetectionResult>.broadcast();
      _isInitialized = true;
      
      // Debug logging instead of print
      assert(() {
        print('Enhanced HumanVoiceDetector initialized successfully');
        return true;
      }());
    } catch (e) {
      throw Exception('Failed to initialize HumanVoiceDetector: $e');
    }
  }
  
  /// Process audio frame with robust humming detection
  Future<VoiceDetectionResult> processAudioFrame(Float32List audioData) async {
    if (!_isInitialized) {
      throw StateError('HumanVoiceDetector not initialized');
    }
    
    try {
      // Step 1: Get raw VAD and pitch results + calculate amplitude
      final audioDataFloat64 = Float64List.fromList(audioData);
      final rawVadResult = _vad.isVoice(audioDataFloat64);
      final rawPitch = await _detectPitch(audioData);
      final amplitude = _calculateAmplitude(audioData);
      
      // Step 2: Add to temporal buffer for smoothing (now includes amplitude)
      _temporalBuffer.addFrame(rawVadResult, rawPitch, amplitude);
      
      // Step 3: Get smoothed and analyzed results
      final smoothedVad = _temporalBuffer.getSmoothedVAD(smoothingWindow);
      final recentPitches = _temporalBuffer.getRecentPitches(smoothingWindow);
      final timeSinceLastPitch = _temporalBuffer.getTimeSinceLastValidPitch();
      final pitchStability = _temporalBuffer.getPitchStability(smoothingWindow);
      final voicedDuration = _temporalBuffer.getCurrentVoicedDuration();
      final hasAmplitudeSpike = _temporalBuffer.hasAmplitudeSpike(smoothingWindow, amplitudeSpikeThreshold);
      
      // Step 4: Apply pitch smoothing to recent valid pitches
      double? smoothedPitch;
      if (recentPitches.isNotEmpty) {
        smoothedPitch = _pitchSmoother.add(recentPitches.last);
      }
      
      // Step 5: Enhanced filtering rules for humming detection
      
      // Rule 1: Frequency range filter (80-300 Hz)
      final bool isInHummingRange = smoothedPitch != null && 
          smoothedPitch >= minHummingFreq && 
          smoothedPitch <= maxHummingFreq;
      
      // Rule 2: Pitch stability check
      final bool isPitchStable = pitchStability >= minPitchStability;
      
      // Rule 3: Minimum duration threshold
      final bool meetsMinDuration = voicedDuration >= minHummingDuration;
      
      // Rule 4: Temporal smoothing / gap tolerance
      final bool withinGapTolerance = timeSinceLastPitch <= gapTolerance;
      
      // Rule 5: VAD + pitch combined decision
      final bool basicHummingCondition = smoothedVad && isInHummingRange && isPitchStable;
      
      // Rule 6: Optional amplitude check (reject sudden spikes)
      final bool passesAmplitudeCheck = !hasAmplitudeSpike;
      
      // Step 6: Determine humming state with comprehensive logic
      bool isHumming = false;
      String resultType = 'silence';
      String? message;
      
      // Track humming start time
      if (basicHummingCondition && passesAmplitudeCheck && _hummingStartTime == null) {
        _hummingStartTime = DateTime.now();
      } else if (!basicHummingCondition || !passesAmplitudeCheck) {
        _hummingStartTime = null;
      }
      
      // Calculate actual humming duration
      final Duration actualHummingDuration = _hummingStartTime != null 
          ? DateTime.now().difference(_hummingStartTime!) 
          : Duration.zero;
      
      if (basicHummingCondition && passesAmplitudeCheck && meetsMinDuration) {
        // All conditions met: clear humming detected
        isHumming = true;
        resultType = 'humming';
        _isCurrentlyHumming = true;
        message = 'Stable humming detected (${actualHummingDuration.inMilliseconds}ms, stability: ${(pitchStability * 100).toStringAsFixed(1)}%)';
        
      } else if (_isCurrentlyHumming && withinGapTolerance && passesAmplitudeCheck) {
        // Continue humming during short gaps (temporal smoothing)
        isHumming = true;
        resultType = 'humming';
        message = 'Continuing through brief gap (${timeSinceLastPitch.inMilliseconds}ms)';
        
      } else if (basicHummingCondition && passesAmplitudeCheck && !meetsMinDuration) {
        // Potential humming but too short duration
        resultType = 'voice';
        _isCurrentlyHumming = false;
        message = 'Voice detected but duration too short (${actualHummingDuration.inMilliseconds}ms < ${minHummingDuration.inMilliseconds}ms)';
        
      } else if (smoothedVad && isInHummingRange && !isPitchStable) {
        // In frequency range but not stable enough (filters speech)
        resultType = 'voice';
        _isCurrentlyHumming = false;
        message = 'Voice in humming range but unstable pitch (stability: ${(pitchStability * 100).toStringAsFixed(1)}%)';
        
      } else if (smoothedVad && !isInHummingRange) {
        // Voice activity but outside humming frequency range
        resultType = 'voice';
        _isCurrentlyHumming = false;
        message = smoothedPitch != null 
            ? 'Voice outside humming range (${smoothedPitch.toStringAsFixed(1)} Hz)'
            : 'Voice activity without clear pitch';
            
      } else if (hasAmplitudeSpike) {
        // Amplitude spike detected (filters sudden loud noises)
        resultType = 'noise';
        _isCurrentlyHumming = false;
        message = 'Amplitude spike detected - likely transient noise';
        
      } else if (!smoothedVad && !withinGapTolerance) {
        // Clear silence
        resultType = 'silence';
        _isCurrentlyHumming = false;
        _hummingStartTime = null;
        
      } else {
        // Ambiguous state - maintain current state briefly with stricter conditions
        if (_isCurrentlyHumming && 
            timeSinceLastPitch <= Duration(milliseconds: 150) && 
            passesAmplitudeCheck) {
          isHumming = true;
          resultType = 'humming';
          message = 'Maintaining humming state during brief uncertainty';
        } else {
          resultType = 'silence';
          _isCurrentlyHumming = false;
          _hummingStartTime = null;
        }
      }
      
      // Step 7: Gender classification if we have a valid pitch
      String? gender;
      if (smoothedPitch != null) {
        gender = _classifyGender(smoothedPitch);
      }
      
      // Step 8: Enhanced confidence calculation
      double confidence = _calculateEnhancedConfidence(
        smoothedVad, 
        isInHummingRange,
        isPitchStable,
        meetsMinDuration,
        passesAmplitudeCheck,
        recentPitches.length,
        timeSinceLastPitch,
        pitchStability
      );
      
      return VoiceDetectionResult(
        status: 'ok',
        type: resultType,
        gender: gender,
        confidence: confidence,
        message: message,
        pitch: smoothedPitch,
        isHumming: isHumming,
      );
      
    } catch (e) {
      return VoiceDetectionResult(
        status: 'error',
        type: 'processing_error',
        message: 'Processing failed: $e',
      );
    }
  }
  
  /// Calculate amplitude (RMS) of audio frame
  double _calculateAmplitude(Float32List audioData) {
    if (audioData.isEmpty) return 0.0;
    
    double sum = 0.0;
    for (final sample in audioData) {
      sum += sample * sample;
    }
    return sqrt(sum / audioData.length);
  }
  
  /// Enhanced confidence calculation with all filtering factors
  double _calculateEnhancedConfidence(
    bool vadResult, 
    bool inHummingRange,
    bool pitchStable,
    bool meetsMinDuration,
    bool passesAmplitudeCheck,
    int recentPitchCount, 
    Duration timeSinceLastPitch,
    double pitchStability
  ) {
    double confidence = 0.3; // Lower base confidence, build up with evidence
    
    // Core requirements
    if (vadResult) confidence += 0.15;
    if (inHummingRange) confidence += 0.15;
    if (pitchStable) confidence += 0.2;
    if (meetsMinDuration) confidence += 0.15;
    if (passesAmplitudeCheck) confidence += 0.1;
    
    // Bonus for consistency
    if (recentPitchCount >= 5) confidence += 0.05;
    if (recentPitchCount >= 8) confidence += 0.05;
    
    // Pitch stability bonus (scaled)
    confidence += pitchStability * 0.1;
    
    // Penalty for gaps
    if (timeSinceLastPitch > Duration(milliseconds: 50)) {
      confidence -= 0.1;
    }
    if (timeSinceLastPitch > Duration(milliseconds: 100)) {
      confidence -= 0.1;
    }
    
    return confidence.clamp(0.0, 1.0);
  }

  /// Detect pitch using existing YIN algorithm
  Future<double?> _detectPitch(Float32List audioData) async {
    try {
      // Convert Float32List to Uint8List (PCM16 format) for EnhancedYin
      final pcmData = _float32ToPcm16(audioData);
      final pitchResult = _yin.processFrame(pcmData, sampleRate);
      if (pitchResult != null && pitchResult > 0) {
        return pitchResult;
      }
      return null;
    } catch (e) {
      // Debug logging instead of print
      assert(() {
        print('Pitch detection failed: $e');
        return true;
      }());
      return null;
    }
  }
  
  /// Convert Float32List to PCM16 format for EnhancedYin
  Uint8List _float32ToPcm16(Float32List samples) {
    final int length = samples.length;
    final Uint8List bytes = Uint8List(length * 2);
    final ByteData view = ByteData.sublistView(bytes);
    for (int i = 0; i < length; i++) {
      double s = samples[i];
      if (s.isNaN || !s.isFinite) s = 0.0;
      s = s.clamp(-1.0, 1.0);
      final int v = (s * 32767.0).round();
      view.setInt16(i * 2, v, Endian.little);
    }
    return bytes;
  }
  
  /// Classify gender based on pitch
  String _classifyGender(double? pitch) {
    if (pitch == null) return 'unknown';
    return pitch < genderThreshold ? 'male' : 'female';
  }
  
  /// Get detection results stream
  Stream<VoiceDetectionResult> get detectionStream {
    if (_resultController == null) {
      throw StateError('HumanVoiceDetector not initialized');
    }
    return _resultController!.stream;
  }
  
  /// Start continuous detection from microphone
  Future<void> startContinuousDetection() async {
    if (!_isInitialized) {
      throw StateError('HumanVoiceDetector not initialized');
    }
    
    // This would integrate with your existing microphone stream
    // Debug logging instead of print
    assert(() {
      print('Continuous detection started - integrate with existing microphone stream');
      return true;
    }());
  }
  
  /// Stop continuous detection
  void stopContinuousDetection() {
    // Debug logging instead of print
    assert(() {
      print('Continuous detection stopped');
      return true;
    }());
  }
  
  /// Dispose resources
  void dispose() {
    _resultController?.close();
    _isInitialized = false;
  }
}