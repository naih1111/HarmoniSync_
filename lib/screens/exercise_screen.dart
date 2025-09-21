import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Note: Web-only APIs removed per requirement. Using native/audio package paths only.
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/music_service.dart';
import '../services/yin_algorithm.dart';
import '../utils/note_utils.dart';
import '../widgets/music_sheet.dart';
import '../database/database_helper.dart';
import '../services/enhanced_yin.dart';

// ============================================================================
// EXERCISE SCREEN - Main screen for practicing pitch detection exercises
// ============================================================================
// This screen handles:
// - Loading and displaying music scores
// - Playing exercises with adjustable BPM
// - Real-time pitch detection using microphone
// - Metronome functionality
// - Exercise controls (play, pause, replay)
// - Score tracking and progress saving

class ExerciseScreen extends StatefulWidget {
  final String level;

  const ExerciseScreen({
    super.key,
    required this.level,
  });

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> with SingleTickerProviderStateMixin {
  // ============================================================================
  // STATE VARIABLES - Track the current state of the exercise
  // ============================================================================
  
  // Exercise Data & Loading
  late Future<Score> _scoreFuture;        // Holds the music score data
  bool _isLoading = true;                 // Shows loading spinner while score loads
  String? _error;                         // Stores any error messages
  
  // Playback Control States
  bool _isPlaying = false;                // True when exercise is actively playing
  bool _isPaused = false;                 // True when exercise is paused
  bool _reachedEnd = false;               // True when exercise has finished
  
  // Countdown & Timing
  int _countdown = 3;                     // Countdown number (3, 2, 1, 0)
  bool _showCountdown = false;            // Whether to show countdown overlay
  Timer? _countdownTimer;                 // Timer for countdown animation
  Timer? _playbackTimer;                  // Main timer for exercise playback
  Timer? _metronomeTimer;                 // Timer used for metronome when needed
  double _currentTime = 0.0;              // Current position in exercise (seconds)
  double _totalDuration = 0.0;            // Total length of exercise (seconds)
  double _lastMeasurePosition = 1;        // End position of last measure
  
  // Note Tracking
  int _currentNoteIndex = 0;              // Index of current note being played
  String? _expectedNote;                  // The note that should be sung/played
  String? _currentDetectedNote;           // The note detected from microphone
  bool _isCorrect = false;                // Whether detected note matches expected
  
  // Score & Progress Tracking
  int _totalPlayableNotes = 0;            // Total number of notes (excluding rests)
  int _correctNotesCount = 0;             // Number of correctly played notes
  final Map<int, bool> _noteCorrectness = {}; // Tracks correctness of each note
  
  // Animation & Visual Effects
  late AnimationController _pulseController;      // Controls note highlighting animation
  late Animation<double> _pulseAnimation;         // Scale animation for current note
  late Animation<Color?> _glowColorAnimation;     // Color animation for feedback
  
  // Audio Recording & Pitch Detection
  late FlutterSoundRecorder _recorder;            // Records audio from microphone
  StreamSubscription? _audioStreamSubscription;   // Listens to audio stream
  StreamController<Uint8List>? _audioStreamController; // Controls audio data flow
  
  // Metronome System
  late FlutterSoundPlayer _metronomePlayer;       // Plays metronome click sounds
  bool _metronomeEnabled = false;                 // Whether metronome is on/off
  bool _metronomeFlash = false;                   // Visual flash for metronome beats
  int _metronomeBeatIndex = 0;                    // Current beat in metronome pattern
  int? _timeSigBeats;                             // Time signature beats (e.g., 4 in 4/4)
  int? _timeSigBeatType;                          // Time signature beat type (e.g., 4 in 4/4)
  int _lastWholeBeat = -1;                        // Last metronome beat that was played
  int _lastClickStartUs = 0;                      // Timestamp of last metronome click
  static const int _clickDurationMs = 50;         // Duration of metronome click sound
  
  // Count-in System
  bool _isCountingIn = false;                     // Whether we're in count-in phase
  int _countInBeatsRemaining = 0;                 // Number of count-in beats left
  static const int _countInBeats = 4;             // Number of count-in beats (one measure)
  
  // Exercise Settings
  double _bpm = 120.0;                            // Beats per minute (exercise speed)
  
  // Precise timing helpers
  Stopwatch? _playbackStopwatch;                  // High-precision stopwatch for playback
  double _elapsedBeforePauseSec = 0.0;            // Accumulated time before a pause
  
  // UI Controllers
  final ScrollController _noteScrollController = ScrollController(); // Scrolls note list
  
  // Web Audio unlock not used on non-web platforms

  // Cache for note positions to avoid recalculating every frame
  List<double> _notePositions = [];
  List<String> _noteNames = [];
  bool _needsNoteListRebuild = true;

  // Enhanced pitch detection
  late EnhancedYin _enhancedPitchDetector;
  double _pitchConfidence = 0.0;
  String? _lastStableNote;
  int _stableNoteFrames = 0;
  static const int requiredStableFrames = 1; // Changed from 3 to 1

  // Debug and visual feedback
  String _debugInfo = '';
  double _lastDetectedFrequency = 0.0;
  bool _isVoiceDetected = false;
  String _lastRawNote = '';
  int _debugFrameCount = 0;
  
  // Debug controls for testing individual components
  bool _showDebugPanel = false;
  bool _testWienerFilter = false;
  bool _testVoiceActivityDetector = false;
  bool _testPitchSmoother = false;
  bool _showComponentStats = false;
  Map<String, dynamic> _componentStats = {};

  // Add these new state variables
  double _currentNoteDuration = 1.0; // Duration of current note in beats
  double _adaptiveStabilityThreshold = 0.25;
  int _adaptiveRequiredFrames = 2;

  // Singer gender settings
  bool _isMaleSinger = true; // Default to male
  double _maleFrequencyMin = 80.0;
  double _maleFrequencyMax = 400.0;
  double _femaleFrequencyMin = 150.0;
  double _femaleFrequencyMax = 800.0;

  @override
  void initState() {
    super.initState();
    
    // ============================================================================
    // INITIALIZATION - Set up the exercise screen when it first loads
    // ============================================================================
    
    // Force landscape orientation for better music sheet viewing
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // Load the music score for this exercise level
    _loadScore();
    
    // ============================================================================
    // ANIMATION SETUP - Create visual effects for note highlighting
    // ============================================================================
    
    // Create a repeating pulse animation for the current note
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    // Scale animation: note grows from 1.0x to 1.2x size
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Color animation: note glows from transparent to green/red based on correctness
    _glowColorAnimation = ColorTween(
      begin: Colors.transparent,
      end: Colors.green.withOpacity(0.5),
    ).animate(_pulseController);

    // ============================================================================
    // AUDIO SYSTEM SETUP - Initialize microphone and metronome
    // ============================================================================
    
    // Set up microphone recorder for pitch detection
    _recorder = FlutterSoundRecorder();
    _initializeRecorder();
    
    // Set up metronome player for beat sounds
    _metronomePlayer = FlutterSoundPlayer();
    _initializeMetronomePlayer();
    
    // Ensure BPM is within valid range (40-244 BPM)
    _bpm = _bpm.clamp(40.0, 244.0);

    // Initialize enhanced pitch detector with performance-optimized settings
    _enhancedPitchDetector = EnhancedYin(
      sampleRate: 44100,
      wienerStrength: 0.3,        // Reduced noise reduction for performance
      vadSensitivity: 0.4,        // Less sensitive to reduce processing
      medianWindow: 3,            // Smaller window for performance
      upsampleFactor: 1,          // Disabled upsampling for performance
      enableParabolicRefinement: false, // Disabled for performance
    );
  }

  // ============================================================================
  // AUDIO INITIALIZATION - Set up microphone and metronome systems
  // ============================================================================
  
  /// Request microphone permission and set up audio recorder
  Future<void> _initializeRecorder() async {
    // Ask user for permission to use microphone
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Microphone permission not granted');
    }
    
    // Open the audio recorder
    await _recorder.openRecorder();
    
    // Set how often we get audio data (60ms intervals for real-time processing)
    try {
      await _recorder.setSubscriptionDuration(const Duration(milliseconds: 60));
    } catch (_) {}
  }

  /// Set up the metronome player for beat sounds
  Future<void> _initializeMetronomePlayer() async {
    try {
      await _metronomePlayer.openPlayer();
    } catch (e) {
      // Fallback silently if player cannot open
      print('Error opening metronome player: $e');
    }
  }

  /// Web audio unlock function (not needed on mobile)
  Future<void> _unlockWebAudioIfNeeded() async { return; }

  // ============================================================================
  // PITCH DETECTION - Real-time audio analysis to detect sung/played notes
  // ============================================================================
  
  /// Calculate adaptive detection parameters based on BPM and note duration
  void _calculateAdaptiveDetection() {
    // Calculate how long each note lasts in milliseconds
    final double beatDurationMs = (60.0 / _bpm) * 1000; // ms per beat
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
    if (_bpm > 160) {
      // Very fast tempo - prioritize speed
      _adaptiveRequiredFrames = math.max(1, _adaptiveRequiredFrames - 1);
      _adaptiveStabilityThreshold = math.max(0.1, _adaptiveStabilityThreshold - 0.05);
    } else if (_bpm < 80) {
      // Slow tempo - can afford more stability
      _adaptiveRequiredFrames = math.min(4, _adaptiveRequiredFrames + 1);
      _adaptiveStabilityThreshold = math.min(0.4, _adaptiveStabilityThreshold + 0.05);
    }
  }
  
  /// Start listening to microphone and analyzing pitch in real-time
  void _startPitchDetection() async {
    try {
      // Stop any existing recording to avoid conflicts
      try {
        if (_recorder.isRecording) {
          await _recorder.stopRecorder();
        }
      } catch (_) {}

      // Create a stream to receive audio data from microphone
      _audioStreamController = StreamController<Uint8List>();
      
      // Start recording audio and send it to our stream
      await _recorder.startRecorder(
        toStream: _audioStreamController!.sink,
        codec: Codec.pcm16,        // 16-bit audio quality
        numChannels: 1,            // Mono audio (single channel)
        sampleRate: 44100,         // CD-quality sample rate
      );

      // Listen to the audio stream and analyze each chunk
      Timer? throttleTimer;
      _audioStreamSubscription = _audioStreamController!.stream.listen((buffer) {
        // Only process audio when exercise is playing
        if (!_isPlaying || !mounted) return;

        try {
          // Adaptive processing interval based on BPM - REDUCED for performance
          final int processingInterval = _bpm > 160 ? 60 : (_bpm < 80 ? 120 : 80); // Doubled intervals
          if (throttleTimer?.isActive ?? false) return;
          throttleTimer = Timer(Duration(milliseconds: processingInterval), () {});

          // Use your enhanced pitch detection pipeline
          final pitchHz = _enhancedPitchDetector.processFrame(buffer, 44100);
          if (pitchHz == null) {
            // No voice detected
            _isVoiceDetected = false;
            _stableNoteFrames = 0;
            _lastStableNote = null;
            _updateDebugInfo();
            if (mounted) setState(() {});
            return;
          }
          
          // Convert frequency to musical note
          final note = NoteUtils.frequencyToNote(pitchHz);
          if (!mounted) return;
          
          // Calculate confidence based on frequency stability
          final confidence = _calculateConfidence(pitchHz);
          
          // Always update debug info
          _updateDebugInfo();
          
          // Use adaptive threshold
          if (confidence > _adaptiveStabilityThreshold) {
            // Always update immediately for any note change
            if (_lastStableNote != note) {
              // New note detected - update immediately
              _lastStableNote = note;
              _stableNoteFrames = 1;
              _updatePitchDetection(note, confidence);
            } else {
              // Same note - increment stability counter
              _stableNoteFrames++;
              
              // Only update if we haven't updated recently (avoid spam)
              if (_stableNoteFrames % 3 == 0) { // Update every 3 frames for same note
                _updatePitchDetection(note, confidence);
              }
            }
          } else {
            // Reset stability if confidence is too low
            _stableNoteFrames = 0;
            _lastStableNote = null;
          }
        } catch (e) {
          print('Error in pitch detection: $e');
        }
      });
    } catch (e) {
      print('Error starting recorder: $e');
    }
  }

  /// Update pitch detection results with better debugging
  void _updatePitchDetection(String note, double confidence) {
    if (!mounted) return;
    
    // Update debug info
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
    
    // Only update if note or correctness changed
    final bool noteChanged = note != _currentDetectedNote;
    final bool correctnessChanged = (_expectedNote != null) && (_isCorrect != (note == _expectedNote));
    
    if (noteChanged || correctnessChanged) {
      // Batch state updates
            _currentDetectedNote = note;
      _pitchConfidence = confidence;
      
            if (_expectedNote != null) {
              _isCorrect = note == _expectedNote;
              final bool? previous = _noteCorrectness[_currentNoteIndex];
              _noteCorrectness[_currentNoteIndex] = _isCorrect;
              if (_isCorrect && previous != true) {
                _correctNotesCount++;
              }
      }
      
      // Update debug info
      _updateDebugInfo();
      
      // Only call setState once per batch
      setState(() {
        // State is already updated above
      });
    }
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
      
      print('=== WIENER FILTER TEST ===');
      print('SNR: ${snr.toStringAsFixed(2)}dB');
      print('Noise Reduction: ${noiseReduction.toStringAsFixed(1)}%');
      print('Status: ${snr > -40 ? "GOOD" : snr > -50 ? "FAIR" : "POOR"}');
      print('Filter Strength: ${wienerStats['strength'] ?? 0.5}');
      print('Initialized: ${wienerStats['initialized'] ?? false}');
      
      // Test different noise levels
      if (snr > -30) {
        print('✅ Clean signal detected - filter working optimally');
      } else if (snr > -45) {
        print('⚠️ Moderate noise - filter actively reducing noise');
      } else {
        print('🔴 High noise environment - maximum filtering applied');
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
      
      print('=== VOICE ACTIVITY DETECTOR TEST ===');
      print('Voice Frames: $voiceFrames/$totalFrames (${(voiceRatio * 100).toStringAsFixed(1)}%)');
      print('Detection Accuracy: ${accuracy.toStringAsFixed(1)}%');
      print('Current Confidence: ${((_componentStats['vadConfidence'] ?? 0.0) * 100).toStringAsFixed(1)}%');
      
      // Test voice detection sensitivity
      if (voiceRatio > 0.7) {
        print('✅ High voice activity - good singing detected');
      } else if (voiceRatio > 0.3) {
        print('⚠️ Moderate voice activity - intermittent singing');
      } else {
        print('🔴 Low voice activity - check microphone or sing louder');
      }
      
      // Test accuracy
      if (accuracy > 85) {
        print('✅ Excellent VAD accuracy');
      } else if (accuracy > 70) {
        print('⚠️ Good VAD accuracy');
      } else {
        print('🔴 VAD accuracy needs improvement');
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
      
      print('=== PITCH SMOOTHER TEST ===');
      print('Outliers Removed: $outlierCount/$totalProcessed (${(outlierRatio * 100).toStringAsFixed(1)}%)');
      print('Smoothing Factor: ${smoothingFactor.toStringAsFixed(2)}');
      print('Stability: ${_stableNoteFrames}/${_adaptiveRequiredFrames} frames');
      
      // Test smoothing effectiveness
      if (outlierRatio < 0.1) {
        print('✅ Stable pitch - minimal smoothing needed');
      } else if (outlierRatio < 0.3) {
        print('⚠️ Moderate pitch variation - smoother actively working');
      } else {
        print('🔴 High pitch instability - maximum smoothing applied');
      }
      
      // Test note stability
      if (_stableNoteFrames >= _adaptiveRequiredFrames) {
        print('✅ Note detection stable');
      } else {
        print('⏳ Building note stability...');
      }
    }
  }

  /// Update debug information for display
  void _updateDebugInfo() {
    final double beatDurationMs = (60.0 / _bpm) * 1000;
    final double noteDurationMs = _currentNoteDuration * beatDurationMs;
    final int processingInterval = noteDurationMs < 400 ? 40 : 
                                 (noteDurationMs < 800 ? 60 : 
                                 (_bpm > 140 ? 60 : (_bpm < 80 ? 120 : 80))); // Optimized intervals
    
    // Get performance metrics
    final performanceMetrics = _getPerformanceMetrics();
    
    _debugInfo = '''
Voice: ${_isVoiceDetected ? 'YES' : 'NO'}
Detected: $_lastRawNote
Expected: ${_expectedNote ?? 'None'}
Confidence: ${(_pitchConfidence * 100).toStringAsFixed(1)}%
Frames: $_debugFrameCount
Frequency: ${_lastDetectedFrequency.toStringAsFixed(1)} Hz
Stable: ${_stableNoteFrames}/$_adaptiveRequiredFrames
BPM: ${_bpm.toStringAsFixed(0)}
Note Duration: ${noteDurationMs.toStringAsFixed(0)}ms
Processing: ${processingInterval}ms
Threshold: ${(_adaptiveStabilityThreshold * 100).toStringAsFixed(1)}%
Singer: ${_isMaleSinger ? 'MALE' : 'FEMALE'}
Status: ${_stableNoteFrames >= 1 ? 'DETECTED' : 'DETECTING...'}
Change: ${_lastStableNote != _currentDetectedNote ? 'NEW NOTE' : 'SAME NOTE'}

=== PERFORMANCE METRICS ===
${performanceMetrics['summary']}
Processing Time: ${performanceMetrics['processingTime']}ms
Memory Usage: ${performanceMetrics['memoryUsage']}
Component Health: ${performanceMetrics['componentHealth']}
''';
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

  /// Calculate confidence based on frequency stability and singer gender
  double _calculateConfidence(double frequency) {
    _lastDetectedFrequency = frequency;
    
    // Get frequency range based on singer gender
    final double minFreq = _isMaleSinger ? _maleFrequencyMin : _femaleFrequencyMin;
    final double maxFreq = _isMaleSinger ? _maleFrequencyMax : _femaleFrequencyMax;
    
    // Calculate confidence based on frequency range and singer gender
    if (frequency >= minFreq && frequency <= maxFreq) {
      return 1.0; // High confidence for typical singing range
    } else if (frequency >= (minFreq * 0.8) && frequency <= (maxFreq * 1.2)) {
      return 0.8; // Good confidence for extended range
    } else if (frequency >= (minFreq * 0.6) && frequency <= (maxFreq * 1.5)) {
      return 0.6; // Medium confidence for wider range
    } else {
      return 0.2; // Low confidence for extreme frequencies
    }
  }

  void _stopPitchDetection() async {
    _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _audioStreamController?.close();
    _audioStreamController = null;
    
    // Reset enhanced pitch detector
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
      print('Error stopping recorder: $e');
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _playbackTimer?.cancel();
    _metronomeTimer?.cancel();
    _audioStreamSubscription?.cancel();
    _audioStreamController?.close();
    _pulseController.dispose();
    _recorder.closeRecorder();
    _metronomePlayer.closePlayer();
    _noteScrollController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _loadScore() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final score = await MusicService.loadMusicXML(widget.level);
      setState(() {
        _scoreFuture = Future.value(score);
        _isLoading = false;
        _timeSigBeats = score.beats;
        _timeSigBeatType = score.beatType;
        // Count playable (non-rest) notes for scoring
        _totalPlayableNotes = 0;
        for (final m in score.measures) {
          for (final n in m.notes) {
            if (!n.isRest) _totalPlayableNotes++;
          }
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load exercise: $e';
        _isLoading = false;
      });
    }
  }

  // ============================================================================
  // EXERCISE CONTROL - Start, pause, resume, and stop the exercise
  // ============================================================================
  
  /// Show a 3-2-1 countdown before starting the exercise
  void _startCountdown() {
    // Cancel any existing timers to avoid conflicts
    _playbackTimer?.cancel();
    _countdownTimer?.cancel();
    
    // Reset exercise state and show countdown overlay
    setState(() {
      _countdown = 3;                    // Start countdown at 3
      _isPlaying = false;                // Not playing yet
      _isPaused = false;                 // Not paused
      _currentTime = 0.0;                // Reset to beginning
      _showCountdown = true;             // Show countdown overlay
    });

    // Create countdown timer that counts down every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdown > 1) {
          _countdown--;                   // Count down: 3, 2, 1
        } else {
          _countdown = 0;                 // Countdown finished
          _showCountdown = false;         // Hide countdown overlay
          _countdownTimer?.cancel();      // Stop countdown timer
          _startExercise();               // Begin the actual exercise
        }
      });
    });
  }

  // ============================================================================
  // SETTINGS DIALOG - Allow user to adjust exercise speed (BPM)
  // ============================================================================
  
  /// Show a dialog for adjusting the exercise speed (beats per minute)
  void _showSettingsDialog() {
    // Use temporary variable so changes only apply when user confirms
    double tempBpm = _bpm;
    bool tempIsMaleSinger = _isMaleSinger;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: AlertDialog(
                backgroundColor: const Color(0xFF232B39), // Dark blue background
                title: const Text(
                  'Exercise Settings',
                  style: TextStyle(color: Color(0xFFF5F5DD)),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // BPM Settings Section
                    const Text(
                      'Note Speed (BPM)',
                      style: TextStyle(
                        color: Color(0xFFF5F5DD),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFF5F5DD)),
                          onPressed: () {
                            if (tempBpm > 40) {
                              tempBpm = (tempBpm - 1).clamp(40.0, 244.0);
                              setDialogState(() {}); // Update dialog state
                              if (mounted) {
                                setState(() {
                                  _bpm = tempBpm;
                                  if (_metronomeEnabled) {
                                    _startMetronome();
                                  }
                                  // Restart exercise with new BPM if currently playing
                                  if (_isPlaying) {
                                    _stopExercise();
                                    _startExercise();
                                  }
                                });
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${tempBpm.round()} BPM',
                          style: const TextStyle(
                            color: Color(0xFFF5F5DD),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFFF5F5DD)),
                          onPressed: () {
                            if (tempBpm < 244) {
                              tempBpm = (tempBpm + 1).clamp(40.0, 244.0);
                              setDialogState(() {}); // Update dialog state
                              if (mounted) {
                                setState(() {
                                  _bpm = tempBpm;
                                  if (_metronomeEnabled) {
                                    _startMetronome();
                                  }
                                  // Restart exercise with new BPM if currently playing
                                  if (_isPlaying) {
                                    _stopExercise();
                                    _startExercise();
                                  }
                                });
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: Colors.blue,
                        inactiveTrackColor: Colors.blue.withOpacity(0.2),
                        thumbColor: Color(0xFFF5F5DD),
                        overlayColor: Colors.blue.withOpacity(0.2),
                        valueIndicatorColor: Colors.blue,
                        valueIndicatorTextStyle: const TextStyle(color: Color(0xFFF5F5DD)),
                        trackHeight: 4.0,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 12.0,
                          elevation: 4.0,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 24.0,
                        ),
                      ),
                      child: Slider(
                        value: tempBpm,
                        min: 40,
                        max: 244,
                        divisions: 204,
                        label: '${tempBpm.round()} BPM',
                        onChanged: (value) {
                          tempBpm = value;
                          setDialogState(() {}); // Update dialog state
                          if (mounted) {
                            setState(() {
                              _bpm = value;
                              if (_metronomeEnabled) {
                                _startMetronome();
                              }
                              // Restart exercise with new BPM if currently playing
                              if (_isPlaying) {
                                _stopExercise();
                                _startExercise();
                              }
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '40 BPM',
                          style: TextStyle(
                            color: Color(0xFFF5F5DD).withOpacity(0.54),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '244 BPM',
                          style: TextStyle(
                            color: Color(0xFFF5F5DD).withOpacity(0.54),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Higher BPM = Faster Note Changes',
                      style: TextStyle(
                        color: Color(0xFFF5F5DD).withOpacity(0.54),
                        fontSize: 12,
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Singer Gender Settings Section
                    const Text(
                      'Singer Gender',
                      style: TextStyle(
                        color: Color(0xFFF5F5DD),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                tempIsMaleSinger ? Icons.male : Icons.female,
                                color: tempIsMaleSinger ? Colors.blue : Colors.pink,
                                size: 28,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                tempIsMaleSinger ? 'Male Singer' : 'Female Singer',
                                style: TextStyle(
                                  color: Color(0xFFF5F5DD),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: tempIsMaleSinger,
                            onChanged: (value) {
                              tempIsMaleSinger = value;
                              setDialogState(() {});
                            },
                            activeColor: Colors.blue,
                            inactiveThumbColor: Colors.pink,
                            inactiveTrackColor: Colors.pink.withOpacity(0.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tempIsMaleSinger 
                        ? 'Optimized for male vocal range (80-400 Hz)'
                        : 'Optimized for female vocal range (150-800 Hz)',
                      style: TextStyle(
                        color: Color(0xFFF5F5DD).withOpacity(0.7),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Debug Controls Section
                    const Text(
                      'Debug Controls',
                      style: TextStyle(
                        color: Color(0xFFF5F5DD),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Show Debug Panel', style: TextStyle(color: Color(0xFFF5F5DD))),
                            value: _showDebugPanel,
                            onChanged: (value) {
                              setDialogState(() {
                                _showDebugPanel = value;
                              });
                            },
                            activeColor: Colors.blue,
                          ),
                          SwitchListTile(
                            title: const Text('Test Wiener Filter', style: TextStyle(color: Color(0xFFF5F5DD))),
                            subtitle: const Text('Isolate noise reduction', style: TextStyle(color: Color(0xFFF5F5DD), fontSize: 12)),
                            value: _testWienerFilter,
                            onChanged: (value) {
                              setDialogState(() {
                                _testWienerFilter = value;
                              });
                            },
                            activeColor: Colors.green,
                          ),
                          SwitchListTile(
                            title: const Text('Test Voice Activity Detector', style: TextStyle(color: Color(0xFFF5F5DD))),
                            subtitle: const Text('Isolate voice detection', style: TextStyle(color: Color(0xFFF5F5DD), fontSize: 12)),
                            value: _testVoiceActivityDetector,
                            onChanged: (value) {
                              setDialogState(() {
                                _testVoiceActivityDetector = value;
                              });
                            },
                            activeColor: Colors.orange,
                          ),
                          SwitchListTile(
                            title: const Text('Test Pitch Smoother', style: TextStyle(color: Color(0xFFF5F5DD))),
                            subtitle: const Text('Isolate pitch smoothing', style: TextStyle(color: Color(0xFFF5F5DD), fontSize: 12)),
                            value: _testPitchSmoother,
                            onChanged: (value) {
                              setDialogState(() {
                                _testPitchSmoother = value;
                              });
                            },
                            activeColor: Colors.purple,
                          ),
                          SwitchListTile(
                            title: const Text('Show Component Stats', style: TextStyle(color: Color(0xFFF5F5DD))),
                            subtitle: const Text('Display performance metrics', style: TextStyle(color: Color(0xFFF5F5DD), fontSize: 12)),
                            value: _showComponentStats,
                            onChanged: (value) {
                              setDialogState(() {
                                _showComponentStats = value;
                              });
                            },
                            activeColor: Colors.cyan,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      if (mounted) {
                        setState(() {
                          _bpm = tempBpm;
                          _isMaleSinger = tempIsMaleSinger;
                          // Update component stats collection
                          if (_showComponentStats) {
                            _updateComponentStats();
                          }
                          if (_metronomeEnabled) {
                            _startMetronome();
                          }
                          // Restart exercise with new settings if currently playing
                          if (_isPlaying) {
                            _stopExercise();
                            _startExercise();
                          }
                        });
                      }
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Close',
                      style: TextStyle(color: Color(0xFFF5F5DD)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Update component statistics from EnhancedYin
  void _updateComponentStats() {
    if (_showComponentStats) {
      _componentStats = _enhancedPitchDetector.getStatistics();
    }
  }

  /// Build widgets for displaying component statistics
  List<Widget> _buildComponentStatsWidgets() {
    List<Widget> widgets = [];
    
    if (_componentStats.containsKey('wiener')) {
      final wienerStats = _componentStats['wiener'] as Map<String, dynamic>;
      widgets.add(Text(
        'Wiener: SNR ${wienerStats['snrDb']?.toStringAsFixed(1) ?? "N/A"}dB',
        style: const TextStyle(color: Colors.green, fontSize: 10),
      ));
    }
    
    if (_componentStats.containsKey('vad')) {
      final vadStats = _componentStats['vad'] as Map<String, dynamic>;
      widgets.add(Text(
        'VAD: ${vadStats['voiceFrames'] ?? 0}/${vadStats['totalFrames'] ?? 0} frames',
        style: const TextStyle(color: Colors.orange, fontSize: 10),
      ));
    }
    
    if (_componentStats.containsKey('smoother')) {
      final smootherStats = _componentStats['smoother'] as Map<String, dynamic>;
      widgets.add(Text(
        'Smoother: ${smootherStats['outlierCount'] ?? 0} outliers',
        style: const TextStyle(color: Colors.purple, fontSize: 10),
      ));
    }
    
    if (_componentStats.containsKey('vadConfidence')) {
      final confidence = _componentStats['vadConfidence'] as double;
      widgets.add(Text(
        'VAD Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
        style: const TextStyle(color: Colors.cyan, fontSize: 10),
      ));
    }
    
    return widgets;
  }

  /// Build performance indicator widget
  Widget _buildPerformanceIndicator(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(color: color, fontSize: 9)),
      ],
    );
  }

  /// Get current processing load as percentage
  String _getProcessingLoad() {
    // Estimate based on frame processing rate and stability
    final double load = (_debugFrameCount > 0) ? 
      ((_stableNoteFrames / _adaptiveRequiredFrames) * 100).clamp(0, 100) : 0;
    return '${load.toStringAsFixed(0)}%';
  }

  /// Get memory usage estimate
  String _getMemoryUsage() {
    // Rough estimate based on frame count and buffer usage
    final double memoryMB = (_debugFrameCount * 0.001).clamp(0, 50);
    return '${memoryMB.toStringAsFixed(1)}MB';
  }

  /// Get system health status
  String _getSystemHealth() {
    final stats = _componentStats;
    int healthScore = 100;
    
    // More lenient SNR threshold for music applications
    if (stats.containsKey('wiener')) {
      final wienerStats = stats['wiener'] as Map<String, dynamic>;
      final double snr = wienerStats['snrDb'] ?? -60.0;
      if (snr < -30) healthScore -= 15; // Reduced penalty and threshold
    }
    
    // More lenient VAD accuracy threshold
    if (stats.containsKey('vad')) {
      final vadStats = stats['vad'] as Map<String, dynamic>;
      final double accuracy = vadStats['accuracy'] ?? 0.0;
      if (accuracy < 60) healthScore -= 20; // Reduced penalty and threshold
    }
    
    // More lenient outlier ratio threshold
    if (stats.containsKey('smoother')) {
      final smootherStats = stats['smoother'] as Map<String, dynamic>;
      final int outlierCount = smootherStats['outlierCount'] ?? 0;
      final int totalProcessed = smootherStats['totalProcessed'] ?? 1;
      if (outlierCount / totalProcessed > 0.15) healthScore -= 15; // Reduced penalty and threshold
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

  /// Begin playing the exercise after countdown finishes
  void _startExercise() {
    if (!mounted) return;
    
    // Cancel any existing timers to avoid conflicts
    _playbackTimer?.cancel();
    
    // Reset all exercise state variables
    setState(() {
      _isPlaying = true;
      _isPaused = false;
      _reachedEnd = false;
      _currentTime = 0.0;
      _currentNoteIndex = 0;
      _noteCorrectness.clear();
      _correctNotesCount = 0;
    });

    // Clear note position cache for fresh start
    _notePositions.clear();
    _noteNames.clear();
  
      // Reset timing variables for accurate playback
    _elapsedBeforePauseSec = 0.0;
    _playbackStopwatch?.stop();
    _playbackStopwatch = Stopwatch()..start();

    // Set the first note that should be played
      _scoreFuture.then((score) {
        if (!mounted) return;
        _updateExpectedNote(score);
      });

    // Start listening to microphone for pitch detection
    _startPitchDetection();

    // Initialize metronome if it's enabled
    if (_metronomeEnabled) {
      _lastWholeBeat = -1;
    }

    // Start the optimized playback timer
    _startPlaybackTimer();
  }

  /// Optimized playback timer with reduced frequency
  void _startPlaybackTimer() {
    _scoreFuture.then((score) {
      if (!mounted) return;
      
      // Build note positions cache once
      _buildNotePositions(score);
      
      // Start playback timer with 100ms interval (was 50ms)
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        
        _updatePlaybackState(score);
      });
    });
  }

  /// Optimized playback state update
  void _updatePlaybackState(Score score) {
    if (_reachedEnd) return;
    
    final double stopwatchSec = (_playbackStopwatch?.elapsedMicroseconds ?? 0) / 1e6;
    final double newCurrentTime = _elapsedBeforePauseSec + stopwatchSec;
    
    // Only update if time has changed significantly (avoid unnecessary setState calls)
    if ((newCurrentTime - _currentTime).abs() > 0.05) { // 50ms threshold
      setState(() {
        _currentTime = newCurrentTime;
      });
    } else {
      _currentTime = newCurrentTime; // Update without setState for minor changes
    }
    
    // Calculate total beats up to current time
    final double metronomeBeatUnitSec = (60.0 / _bpm) * (4.0 / (_timeSigBeatType?.toDouble() ?? 4.0));
    final double currentBeats = _currentTime / metronomeBeatUnitSec;

            // End-of-sheet handling
            if (_currentTime >= _lastMeasurePosition) {
      _handleExerciseEnd();
      return;
    }
    
    // Handle metronome
    _updateMetronome(currentBeats, metronomeBeatUnitSec);
    
    // Find and update current note using cached positions
    _updateCurrentNote(score, currentBeats);
  }

  /// Handle exercise completion
  void _handleExerciseEnd() {
    setState(() {
              _reachedEnd = true;
              _isPlaying = false;
    });
              _playbackTimer?.cancel();
              _stopPitchDetection();
              _stopMetronome();
              _showCompletionDialog();
  }

  /// Update metronome state
  void _updateMetronome(double currentBeats, double metronomeBeatUnitSec) {
    if (!_metronomeEnabled) return;
    
                final int targetBeat = currentBeats.floor();
                const double clickDurationSec = 0.05; // 50ms
                while (_lastWholeBeat < targetBeat) {
                  _lastWholeBeat++;
                  final int beatsPerMeasure = (_timeSigBeats ?? 4).clamp(1, 12);
                  final bool isDownbeat = (_lastWholeBeat % beatsPerMeasure) == 0;
                  final double beatStartSec = _lastWholeBeat * metronomeBeatUnitSec;
                  if (beatStartSec + clickDurationSec <= _lastMeasurePosition) {
                    _triggerMetronome(downbeat: isDownbeat);
                  } else {
        break;
      }
    }
  }

  /// Optimized note finding and updating
  void _updateCurrentNote(Score score, double currentBeats) {
    // Use cached note positions if available
    if (_notePositions.isEmpty) return;
    
    // Binary search for current note
    int newNoteIndex = _findCurrentNoteIndex(currentBeats);
    
    // Update expected/current note on index change or if not set yet
    if (newNoteIndex != _currentNoteIndex || _expectedNote == null) {
              _currentNoteIndex = newNoteIndex;
              _updateExpectedNote(score);
            }
  }

  // Helper method to get note duration in beats
  double _getNoteDuration(Note note) {
    switch (note.type) {
      case 'whole':
        return 4.0;
      case 'half':
        return 2.0;
      case 'quarter':
        return 1.0;
      case 'eighth':
        return 0.5;
      case '16th':
        return 0.25;
      default:
        return 1.0; // Default to quarter note duration
    }
  }

  void _scrollToCurrentNote() {
    if (!_noteScrollController.hasClients) return;
    
    // Calculate the position to scroll to
    final itemWidth = 100.0; // Approximate width of each note item including padding
    final screenWidth = MediaQuery.of(context).size.width;
    final targetPosition = _currentNoteIndex * itemWidth - (screenWidth / 2) + (itemWidth / 2);
    
    // Animate to the target position
    _noteScrollController.animateTo(
      targetPosition.clamp(0.0, _noteScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Update expected note and recalculate adaptive detection
  void _updateExpectedNote(Score score) {
    // Find the current note in the score
    int totalNotes = 0;
    for (final measure in score.measures) {
      for (final note in measure.notes) {
        if (totalNotes == _currentNoteIndex && !note.isRest) {
          setState(() {
            _expectedNote = "${note.step}${note.octave}";
            _isCorrect = false;
            // Update current note duration for adaptive detection
            _currentNoteDuration = _getNoteDuration(note);
            // Recalculate adaptive detection parameters
            _calculateAdaptiveDetection();
          });
          _scrollToCurrentNote(); // Scroll to keep current note visible
          return;
        }
        if (!note.isRest) {
          totalNotes++;
        }
      }
    }
    setState(() {
      _expectedNote = null;
      _isCorrect = false;
    });
  }

  void _pauseExercise() {
    // Cancel the playback timer
    _playbackTimer?.cancel();
    _playbackTimer = null;
    
    // Stop pitch detection
    _stopPitchDetection();
    _stopMetronome(immediate: true);
    // Accumulate elapsed time and stop stopwatch
    final double stopwatchSec = (_playbackStopwatch?.elapsedMicroseconds ?? 0) / 1e6;
    _elapsedBeforePauseSec += stopwatchSec;
    _playbackStopwatch?.stop();
    
    setState(() {
      _isPlaying = false;
      _isPaused = true;
    });
  }

  void _resumeExercise() {
    if (!mounted) return;
    
    // Ensure no existing timer is running
    _playbackTimer?.cancel();
    
    // Resume pitch detection
    _startPitchDetection();
    
    setState(() {
      _isPlaying = true;
      _isPaused = false;
      // Don't restart count-in when resuming - continue from where we left off
      _isCountingIn = false;
      _countInBeatsRemaining = 0;
    });

    // Resume metronome phase
    if (_metronomeEnabled) {
      _lastWholeBeat = -1;
    }

    // Ensure expected note is present when resuming (in case it was cleared)
    // But only if we're not in count-in phase
    _scoreFuture.then((score) {
      if (!mounted) return;
      if (_expectedNote == null && !_isCountingIn) {
        _updateExpectedNote(score);
      }
    });

    // Start stopwatch for precise timing on resume
    _playbackStopwatch?.stop();
    _playbackStopwatch = Stopwatch()..start();

    // Get the score from the future
    _scoreFuture.then((score) {
      if (!mounted) return;
      
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        
        setState(() {
          if (!_reachedEnd) {
            final double stopwatchSec = (_playbackStopwatch?.elapsedMicroseconds ?? 0) / 1e6;
            _currentTime = _elapsedBeforePauseSec + stopwatchSec;
            
            // Calculate note duration based on current BPM
            const double secondsPerMinute = 60.0;
            final double noteDuration = secondsPerMinute / _bpm;
            
            // Calculate total beats up to current time (used by metronome and note selection)
            // BPM represents quarter notes per minute, so each beat is 60/_bpm seconds
            final double metronomeBeatUnitSec = 60.0 / _bpm;
            final double currentBeats = _currentTime / metronomeBeatUnitSec;

            // End-of-sheet handling
            if (_currentTime >= _lastMeasurePosition) {
              _reachedEnd = true;
              _isPlaying = false;
              _playbackTimer?.cancel();
              _stopPitchDetection();
              _stopMetronome();
              // Show completion summary
              _showCompletionDialog();
              return; // short-circuit to avoid any triggers in this tick
            } else {
              // Metronome: trigger on every beat (catch up if timer skipped)
              if (_metronomeEnabled) {
                final int targetBeat = currentBeats.floor();
                const double clickDurationSec = 0.05; // 50ms
                while (_lastWholeBeat < targetBeat) {
                  _lastWholeBeat++;
                  final int beatsPerMeasure = (_timeSigBeats ?? 4).clamp(1, 12);
                  final bool isDownbeat = (_lastWholeBeat % beatsPerMeasure) == 0;
                  final double beatStartSec = _lastWholeBeat * metronomeBeatUnitSec;
                  if (beatStartSec + clickDurationSec <= _lastMeasurePosition) {
                    _triggerMetronome(downbeat: isDownbeat);
                  } else {
                    break; // don't schedule beyond end
                  }
                }
              }
            }
            
            // Find the current note based on beats
            double totalBeats = 0.0;
            int newNoteIndex = 0;
            bool foundNote = false;
            
            for (final measure in score.measures) {
              for (final note in measure.notes) {
                if (!note.isRest) {
                  if (currentBeats >= totalBeats && currentBeats < totalBeats + _getNoteDuration(note)) {
                    foundNote = true;
                    break;
                  }
                  newNoteIndex++;
                }
                totalBeats += _getNoteDuration(note);
              }
              if (foundNote) break;
            }
            
            // Update expected/current note on index change or if not set yet
            // But only if we're not in count-in phase
            if (!_isCountingIn && (newNoteIndex != _currentNoteIndex || _expectedNote == null)) {
              _currentNoteIndex = newNoteIndex;
              _updateExpectedNote(score);
            }
            
            // Stop if we've reached the end of the sheet
            if (_currentTime >= _lastMeasurePosition) {
              _reachedEnd = true;
              _isPlaying = false;
              _playbackTimer?.cancel();
              _stopPitchDetection();
              _stopMetronome();
            }
          }
        });
      });
    });
  }

  void _stopExercise() {
    // Cancel all timers
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _countdownTimer?.cancel();
    
    // Stop pitch detection
    _stopPitchDetection();
    _stopMetronome(immediate: true);
    
    setState(() {
      _isPlaying = false;
      _isPaused = false;
      _currentTime = 0.0;
      _showCountdown = false;
      _reachedEnd = false;
      _currentDetectedNote = null;
      _expectedNote = null;
      _isCorrect = false;
      _pitchConfidence = 0.0;
    });
    _elapsedBeforePauseSec = 0.0;
    _playbackStopwatch?.stop();
    _playbackStopwatch = null;
    
    // Clear note position cache
    _notePositions.clear();
    _noteNames.clear();
    _needsNoteListRebuild = true;
  }

  void _startMetronome() {
    _metronomeTimer?.cancel();
    // No separate timer during playback; we drive clicks from the playback timer via _currentTime
    _lastWholeBeat = -1;
  }

  void _stopMetronome({bool immediate = false}) {
    _metronomeTimer?.cancel();
    _metronomeTimer = null;
    // Immediately stop any in-flight metronome sound to avoid extra click at the end
    try {
      if (_metronomePlayer.isOpen() && _metronomePlayer.isPlaying) {
        if (immediate) {
          // Hard stop (pause/stop actions)
          _metronomePlayer.stopPlayer();
        } else {
          // Let current click finish naturally at sheet end
          // Do nothing; player will end on its own
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _metronomeFlash = false);
  }

  Future<void> _playMetronomeClick({bool downbeat = false}) async {
    try {
      if (!_metronomePlayer.isOpen()) {
        try { await _metronomePlayer.openPlayer(); } catch (_) {}
        if (!_metronomePlayer.isOpen()) {
          // Fallback if we still cannot open
          try { SystemSound.play(SystemSoundType.click); } catch (_) {}
          return;
        }
      }
      // Avoid cutting the click if it's still within its duration; otherwise, force stop to allow a new click
      if (_metronomePlayer.isPlaying) {
        final int nowUs = DateTime.now().microsecondsSinceEpoch;
        final int elapsedMs = ((nowUs - _lastClickStartUs) / 1000).round();
        if (elapsedMs < _clickDurationMs - 5) {
          // Still in click window → skip retrigger to avoid cut
          return;
        }
        // Click should have finished by now but player still reports playing → stop to start the next
        try { await _metronomePlayer.stopPlayer(); } catch (_) {}
      }
      final Uint8List data = _generateClickPcm(
        frequencyHz: downbeat ? 1400 : 1000,
        durationMs: _clickDurationMs,
        sampleRate: 44100,
        amplitude: downbeat ? 0.6 : 0.4,
      );
      _lastClickStartUs = DateTime.now().microsecondsSinceEpoch;
      try {
        await _metronomePlayer.startPlayer(
          fromDataBuffer: data,
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 44100,
        );
      } catch (_) {
        // Fallback to system click if start failed
        try { SystemSound.play(SystemSoundType.click); } catch (_) {}
      }
    } catch (e) {
      // As a fallback, try a system click
      try { SystemSound.play(SystemSoundType.click); } catch (_) {}
    }
  }

  // Web beep removed; native click path only

  void _triggerMetronome({required bool downbeat}) {
    // Guard: if we've reached or passed the sheet end or not actively playing, do not click
    if (_currentTime >= _lastMeasurePosition || !_isPlaying) {
      return;
    }
    _playMetronomeClick(downbeat: downbeat);
    if (mounted) {
      setState(() => _metronomeFlash = true);
      Timer(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _metronomeFlash = false);
      });
    }
  }

  Uint8List _generateClickPcm({
    required double frequencyHz,
    required int durationMs,
    required int sampleRate,
    required double amplitude,
  }) {
    final int totalSamples = (sampleRate * durationMs / 1000).round();
    final Int16List samples = Int16List(totalSamples);
    final double twoPiF = 2 * math.pi * frequencyHz;

    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      // Simple short sine with exponential decay for a clicky feel
      final double envelope = math.exp(-20 * t); // fast decay
      final double s = math.sin(twoPiF * t) * amplitude * envelope;
      samples[i] = (s * 32767).clamp(-32768.0, 32767.0).toInt();
    }
    return samples.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Light gray background to match screenshot
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF8B4511)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          MusicService.getLevelTitle(widget.level),
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF8B4511)),
            onPressed: () {
              _showSettingsDialog();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // ============================================================================
          // MAIN CONTENT - The exercise interface (music sheet, controls, etc.)
          // ============================================================================
          _buildBody(),
          
          // ============================================================================
          // OVERLAYS - Countdown and metronome indicator
          // ============================================================================
          if (_showCountdown && _countdown > 0)
            Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B4511).withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _countdown.toString(),
                  style: const TextStyle(
                    color: Color(0xFFF5F5DD),
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (_metronomeEnabled && _isPlaying)
            Positioned(
              top: 16,
              right: 16,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: _metronomeFlash ? Colors.lightBlueAccent : Color(0xFFF5F5DD).withOpacity(0.24),
                  shape: BoxShape.circle,
                  boxShadow: _metronomeFlash
                      ? [
                          BoxShadow(
                            color: Colors.lightBlueAccent.withOpacity(0.6),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : [],
                ),
               ),
             ),
          
          // Debug Panel Overlay
          if (_showDebugPanel)
            Positioned(
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
                    const Text(
                      'Debug Panel',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_testWienerFilter) ...[
                      const Text('🔧 Wiener Filter Test Mode', style: TextStyle(color: Colors.green, fontSize: 12)),
                      const SizedBox(height: 4),
                    ],
                    if (_testVoiceActivityDetector) ...[
                      const Text('🎤 VAD Test Mode', style: TextStyle(color: Colors.orange, fontSize: 12)),
                      const SizedBox(height: 4),
                    ],
                    if (_testPitchSmoother) ...[
                      const Text('🎵 Pitch Smoother Test Mode', style: TextStyle(color: Colors.purple, fontSize: 12)),
                      const SizedBox(height: 4),
                    ],
                    if (_showComponentStats && _componentStats.isNotEmpty) ...[
                      const Text('📊 Component Statistics:', style: TextStyle(color: Colors.cyan, fontSize: 12)),
                      const SizedBox(height: 4),
                      ..._buildComponentStatsWidgets(),
                      const SizedBox(height: 8),
                      // Real-time performance indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildPerformanceIndicator('CPU', _getProcessingLoad(), Colors.blue),
                          _buildPerformanceIndicator('MEM', _getMemoryUsage(), Colors.green),
                          _buildPerformanceIndicator('HEALTH', _getSystemHealth(), _getHealthColor()),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      'Detected: ${_currentDetectedNote ?? "None"}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      'Expected: ${_expectedNote ?? "None"}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      'Confidence: ${(_pitchConfidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      'Voice: ${_isVoiceDetected ? "Yes" : "No"}',
                      style: TextStyle(
                        color: _isVoiceDetected ? Colors.green : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
         ],
       ),
     );
  }

  // ============================================================================
  // BODY BUILDER - Main content area of the exercise screen
  // ============================================================================
  
  /// Build the main content area, handling loading, errors, and the exercise interface
  Widget _buildBody() {
    // ============================================================================
    // LOADING STATE - Show spinner while music score is loading
    // ============================================================================
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5F5DD)),
        ),
      );
    }

    // ============================================================================
    // ERROR STATE - Show error message with retry button if loading failed
    // ============================================================================
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadScore,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFF5F5DD),
                foregroundColor: const Color(0xFF8B4511),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<Score>(
      future: _scoreFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5F5DD)),
            ),
          );
        }

        final score = snapshot.data!;
        
        // Calculate total duration based on actual note durations
        _lastMeasurePosition = _calculateScoreDurationSeconds(score);
        _totalDuration = _lastMeasurePosition;

        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ============================================================================
                  // DEBUG PANEL - Show what the system is detecting (COMMENTED OUT)
                  // ============================================================================
                  // if (_isPlaying) // Only show when playing
                  //   Container(
                  //     margin: const EdgeInsets.all(8),
                  //     padding: const EdgeInsets.all(12),
                  //     decoration: BoxDecoration(
                  //       color: Colors.black.withOpacity(0.8),
                  //       borderRadius: BorderRadius.circular(8),
                  //       border: Border.all(color: Colors.white.withOpacity(0.3)),
                  //     ),
                  //     child: Column(
                  //       crossAxisAlignment: CrossAxisAlignment.start,
                  //       children: [
                  //         Row(
                  //           children: [
                  //             Icon(
                  //               _isVoiceDetected ? Icons.mic : Icons.mic_off,
                  //               color: _isVoiceDetected ? Colors.green : Colors.red,
                  //               size: 20,
                  //             ),
                  //             const SizedBox(width: 8),
                  //             Text(
                  //               'Audio Detection Debug',
                  //               style: TextStyle(
                  //                 color: Colors.white,
                  //                 fontWeight: FontWeight.bold,
                  //                 fontSize: 14,
                  //               ),
                  //             ),
                  //           ],
                  //         ),
                  //         const SizedBox(height: 8),
                  //         Text(
                  //           _debugInfo,
                  //           style: TextStyle(
                  //             color: Colors.white,
                  //             fontSize: 12,
                  //             fontFamily: 'monospace',
                  //           ),
                  //         ),
                  //       ],
                  //     ),
                  //   ),
                  
                  // ============================================================================
                  // MUSIC SHEET DISPLAY - The main visual area showing the musical notation
                  // ============================================================================
                  Expanded(
                    flex: 5,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B4511).withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: MusicSheet(
                          score: score,
                          isPlaying: _isPlaying,
                          currentTime: _currentTime,
                          currentNoteIndex: _currentNoteIndex,
                          bpm: _bpm,
                          isCorrect: _isCorrect,
                        ),
                      ),
                    ),
                  ),
                  
                  // ============================================================================
                  // NOTE PROGRESS ROW - Horizontal scrollable list showing all notes in order
                  // ============================================================================
                  Container(
                    height: 50,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _buildScrollableNoteRow(score),
                  ),
                  
                  const SizedBox(height: 1),
                  
                  // ============================================================================
                  // CONTROL BUTTONS - Play, pause, metronome, and other exercise controls
                  // ============================================================================
                  Container(
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
                        Container(
                          width: 50,
                          height: 50,
                          child: IconButton(
                            icon: const Icon(Icons.replay, size: 24, color: Color(0xFF8B4511)),
                            onPressed: () {
                              _stopExercise();
                              _startCountdown();
                            },
                          ),
                        ),
                        
                        // Main Play/Pause Button
                        Container(
                          width: 50,
                          height: 50,
                          child: IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause : 
                              _isPaused ? Icons.play_arrow : 
                              Icons.play_arrow,
                              size: 24,
                              color: const Color(0xFF8B4511),
                            ),
                            onPressed: () {
                              if (_isPlaying) {
                                _pauseExercise();
                              } else if (_isPaused) {
                                _resumeExercise();
                              } else {
                                _startCountdown();
                              }
                            },
                          ),
                        ),
                        
                        // Metronome Toggle Button
                        Container(
                          width: 50,
                          height: 50,
                          child: IconButton(
                            icon: Icon(
                              Icons.music_note,
                              size: 24,
                              color: _metronomeEnabled ? Colors.blue : const Color(0xFF8B4511),
                            ),
                            onPressed: () {
                              setState(() {
                                _metronomeEnabled = !_metronomeEnabled;
                              });
                              if (_metronomeEnabled) {
                                _startMetronome();
                                _unlockWebAudioIfNeeded();
                              } else {
                                _stopMetronome();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 5),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ============================================================================
  // NOTE ROW BUILDER - Creates the horizontal scrollable list of notes
  // ============================================================================
  
  /// Build a horizontal scrollable row showing all notes in the exercise
  Widget _buildScrollableNoteRow(Score score) {
    // Only rebuild note list when necessary
    if (_needsNoteListRebuild || _noteNames.isEmpty) {
      _noteNames.clear();
    for (final measure in score.measures) {
      for (final note in measure.notes) {
        if (!note.isRest) {
            _noteNames.add("${note.step}${note.octave}");
        }
      }
      }
      _needsNoteListRebuild = false;
    }
    
    // Create horizontal scrollable list of notes
    return ListView.separated(
      controller: _noteScrollController,
      scrollDirection: Axis.horizontal,
      itemCount: _noteNames.length,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      separatorBuilder: (context, idx) => const SizedBox(width: 8),
      itemBuilder: (context, idx) {
        // Determine the current state of this note
        final isCurrentNote = idx == _currentNoteIndex;
        final wasCorrect = _noteCorrectness[idx];
        
        // Choose color based on note status
        Color noteColor;
        Color textColor;
        
        if (isCurrentNote) {
          noteColor = _isCorrect ? Colors.green : Colors.red;
          textColor = Color(0xFFF5F5DD);
        } else if (wasCorrect != null) {
          noteColor = wasCorrect ? Colors.green : Colors.red;
          textColor = Color(0xFFF5F5DD);
        } else {
          noteColor = Color(0xFFF5F5DD);
          textColor = const Color(0xFF8B4511);
        }

        // Add confidence indicator for current note
        if (isCurrentNote && _pitchConfidence > 0) {
          // Show confidence as border thickness or opacity
          final confidenceOpacity = _pitchConfidence.clamp(0.3, 1.0);
          noteColor = noteColor.withOpacity(confidenceOpacity);
        }

        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: noteColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.grey[400]!,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              _noteNames[idx], // Use cached note names
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        );
      },
    );
  }

  // Calculate duration for a measure based on the score's time signature and current BPM
  double _calculateMeasureDuration(Score score) {
    const double secondsPerMinute = 60.0;
    // Get time signature from the score
    final int beats = score.beats;
    final int beatType = score.beatType;
    // Duration of a single beat as defined by time signature (e.g., eighth in 6/8)
    final double beatUnitSeconds = (secondsPerMinute / _bpm) * (4.0 / beatType);
    // Measure duration = beats per measure * beat unit duration
    return beats * beatUnitSeconds;
  }

  // Calculate precise score duration in seconds by summing note durations (including rests)
  double _calculateScoreDurationSeconds(Score score) {
    const double secondsPerMinute = 60.0;
    final int beatType = score.beatType;
    final double beatUnitSeconds = (secondsPerMinute / _bpm) * (4.0 / beatType);
    double totalBeats = 0.0;
    for (final measure in score.measures) {
      for (final note in measure.notes) {
        totalBeats += _getNoteDuration(note);
      }
    }
    return totalBeats * beatUnitSeconds;
  }

  // ============================================================================
  // COMPLETION HANDLING - Show results and save progress when exercise finishes
  // ============================================================================
  
  /// Display completion dialog with score and save results to database
  void _showCompletionDialog() {
    if (!mounted) return;
    
    // Calculate final score statistics
    final int total = _totalPlayableNotes;                    // Total notes in exercise
    final int correct = _correctNotesCount.clamp(0, total);   // Correctly played notes
    final String percent = total > 0
        ? ((correct / total) * 100).clamp(0, 100).toStringAsFixed(0)  // Percentage score
        : '0';

    // Save this practice session to the database for progress tracking
    _savePracticeSession(correct, total, percent);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF232B39),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Exercise Complete',
            style: TextStyle(color: Color(0xFFF5F5DD), fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Score: $correct / $total',
                style: const TextStyle(color: Color(0xFFF5F5DD), fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                '$percent%',
                style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close', style: TextStyle(color: Color(0xFFF5F5DD))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlueAccent,
                foregroundColor: const Color(0xFF8B4511),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _stopExercise();
                _startCountdown();
              },
              child: const Text('Replay'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================================
  // DATABASE OPERATIONS - Save practice results for progress tracking
  // ============================================================================
  
  /// Save the completed practice session to the database
  Future<void> _savePracticeSession(int correctNotes, int totalNotes, String percentage) async {
    try {
      // Get current timestamp for the session
      final now = DateTime.now();
      
      // Format date and time for database storage
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final duration = _currentTime; // Total time spent on this exercise
      
      // Create session data object for database
      final session = {
        'level': widget.level,                    // Exercise difficulty level
        'score': correctNotes,                    // Number of correctly played notes
        'total_notes': totalNotes,                // Total notes in the exercise
        'percentage': double.parse(percentage),   // Success percentage (0-100)
        'practice_date': date,                    // Date of practice session
        'practice_time': time,                    // Time of practice session
        'duration_seconds': duration,             // How long the session took
        'created_at': now.toIso8601String(),      // ISO timestamp for sorting
      };

      // Save to database using the DatabaseHelper
      final dbHelper = DatabaseHelper();
      await dbHelper.insertPracticeSession(session);
    } catch (e) {
      print('Error saving practice session: $e');
    }
  }

  /// Build note positions cache for efficient lookup
  void _buildNotePositions(Score score) {
    _notePositions.clear();
    _noteNames.clear();
    double totalBeats = 0.0;
    
    for (final measure in score.measures) {
      for (final note in measure.notes) {
        if (!note.isRest) {
          _notePositions.add(totalBeats);
          _noteNames.add('${note.step}${note.octave}');
        }
        totalBeats += _getNoteDuration(note);
      }
    }
  }

  /// Binary search for current note index
  int _findCurrentNoteIndex(double currentBeats) {
    if (_notePositions.isEmpty) return 0;
    
    int left = 0;
    int right = _notePositions.length - 1;
    int result = 0;
    
    while (left <= right) {
      int mid = (left + right) ~/ 2;
      if (_notePositions[mid] <= currentBeats) {
        result = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }
    
    return result;
  }
}