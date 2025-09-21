import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/music_service.dart';
import '../widgets/music_sheet.dart';
import '../database/database_helper.dart';

class ConvertedMusicScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const ConvertedMusicScreen({
    Key? key,
    required this.filePath,
    required this.fileName,
  }) : super(key: key);

  @override
  State<ConvertedMusicScreen> createState() => _ConvertedMusicScreenState();
}

class _ConvertedMusicScreenState extends State<ConvertedMusicScreen>
    with TickerProviderStateMixin {
  // ============================================================================
  // SESSION DATA LOADING
  // ============================================================================
  bool _isLoading = true;
  String? _error;
  Future<Score>? _scoreFuture;

  // ============================================================================
  // PLAYBACK CONTROL
  // ============================================================================
  bool _isPlaying = false;
  bool _isPaused = false;
  double _currentTime = 0.0;
  Timer? _playbackTimer;
  Stopwatch? _playbackStopwatch;
  double _elapsedBeforePauseSec = 0.0;

  // ============================================================================
  // COUNTDOWN & TIMING
  // ============================================================================
  bool _showCountdown = false;
  int _countdown = 3;
  Timer? _countdownTimer;
  bool _isCountingIn = false;

  // ============================================================================
  // NOTE TRACKING
  // ============================================================================
  int _currentNoteIndex = 0;
  String? _expectedNote;
  String? _currentDetectedNote;
  bool _isCorrect = false;
  bool _reachedEnd = false;
  double _lastMeasurePosition = 0.0;
  double _totalDuration = 0.0;

  // ============================================================================
  // SCORE & PROGRESS TRACKING
  // ============================================================================
  int _correctNotesCount = 0;
  int _totalPlayableNotes = 0;
  Map<int, bool> _noteCorrectness = {};

  // ============================================================================
  // ANIMATIONS & VISUAL EFFECTS
  // ============================================================================
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _glowController;
  late Animation<Color?> _glowColorAnimation;

  // ============================================================================
  // AUDIO RECORDING & PITCH DETECTION
  // ============================================================================
  FlutterSoundRecorder? _recorder;
  bool _isRecorderInitialized = false;
  StreamSubscription<RecordingDisposition>? _recordingDataSubscription;
  StreamController<Uint8List>? _audioStreamController;
  double _pitchConfidence = 0.0;
  bool _isVoiceDetected = false;
  String _debugInfo = '';

  // ============================================================================
  // METRONOME SYSTEM
  // ============================================================================
  FlutterSoundPlayer? _metronomePlayer;
  Timer? _metronomeTimer;
  bool _metronomeEnabled = false;
  bool _metronomeFlash = false;
  int _lastWholeBeat = -1;
  int _lastClickStartUs = 0;
  static const int _clickDurationMs = 100;

  // ============================================================================
  // COUNTING SYSTEM
  // ============================================================================
  int _bpm = 120;

  // ============================================================================
  // EXERCISE SETTINGS
  // ============================================================================
  bool _adaptiveDetection = true;
  double _detectionSensitivity = 0.7;
  double _confidenceThreshold = 0.6;

  // ============================================================================
  // PRECISE TIMING HELPERS
  // ============================================================================
  List<double> _notePositions = [];
  List<String> _noteNames = [];
  bool _needsNoteListRebuild = true;
  ScrollController _noteScrollController = ScrollController();

  // ============================================================================
  // UI CONTROLLERS
  // ============================================================================
  bool _showDebugPanel = false;

  // ============================================================================
  // ENHANCED PITCH DETECTION
  // ============================================================================
  List<double> _pitchHistory = [];
  List<double> _confidenceHistory = [];
  static const int _historyLength = 10;
  double _smoothedPitch = 0.0;
  double _smoothedConfidence = 0.0;

  // ============================================================================
  // DEBUG & VISUAL FEEDBACK
  // ============================================================================
  Map<String, dynamic> _componentStats = {};
  bool _showComponentStats = false;

  // ============================================================================
  // DEBUG CONTROLS
  // ============================================================================
  bool _testWienerFilter = false;
  bool _testVoiceActivityDetector = false;
  bool _testPitchSmoother = false;

  // ============================================================================
  // NEW STATE VARIABLES
  // ============================================================================
  String _singerGender = 'mixed'; // 'male', 'female', 'mixed'
  bool _isMaleSinger = false; // For switch toggle compatibility

  @override
  void initState() {
    super.initState();
    
    // Force landscape orientation for better music sheet viewing
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Load the music score from file
    _loadScore();

    // Initialize animations for visual feedback
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _glowColorAnimation = ColorTween(
      begin: Colors.transparent,
      end: Colors.green.withOpacity(0.3),
    ).animate(_glowController);

    // Initialize audio systems
    _initializeRecorder();
    _initializeMetronomePlayer();
    _unlockWebAudioIfNeeded();
  }

  // ============================================================================
  // AUDIO SYSTEM INITIALIZATION
  // ============================================================================

  /// Initialize the audio recorder for pitch detection
  Future<void> _initializeRecorder() async {
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        setState(() {
          _error = 'Microphone permission is required for pitch detection';
        });
        return;
      }

      // Initialize the recorder
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      _isRecorderInitialized = true;
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize audio recorder: $e';
      });
    }
  }

  /// Initialize the metronome audio player
  Future<void> _initializeMetronomePlayer() async {
    try {
      _metronomePlayer = FlutterSoundPlayer();
      await _metronomePlayer!.openPlayer();
    } catch (e) {
      print('Failed to initialize metronome player: $e');
    }
  }

  /// Unlock Web Audio context if needed (for web platform)
  void _unlockWebAudioIfNeeded() {
    // This is a placeholder for web audio context unlocking
    // In a real implementation, you might need platform-specific code
  }

  // ============================================================================
  // ADAPTIVE DETECTION SYSTEM
  // ============================================================================

  /// Calculate adaptive detection parameters based on user performance
  void _calculateAdaptiveDetection() {
    if (!_adaptiveDetection) return;

    // Analyze recent performance to adjust detection sensitivity
    final recentCorrectness = _noteCorrectness.values
        .where((correct) => correct != null)
        .map((correct) => correct! ? 1.0 : 0.0)
        .toList();

    if (recentCorrectness.length >= 5) {
      final accuracy = recentCorrectness.reduce((a, b) => a + b) / recentCorrectness.length;
      
      // Adjust sensitivity based on accuracy
      if (accuracy > 0.8) {
        // High accuracy - can be more strict
        _detectionSensitivity = math.min(0.9, _detectionSensitivity + 0.05);
        _confidenceThreshold = math.min(0.8, _confidenceThreshold + 0.05);
      } else if (accuracy < 0.5) {
        // Low accuracy - be more lenient
        _detectionSensitivity = math.max(0.5, _detectionSensitivity - 0.05);
        _confidenceThreshold = math.max(0.4, _confidenceThreshold - 0.05);
      }
    }
  }

  // ============================================================================
  // PITCH DETECTION SYSTEM
  // ============================================================================

  /// Start continuous pitch detection during exercise playback
  void _startPitchDetection() async {
    if (!_isRecorderInitialized || _recorder == null) return;

    try {
      // Create a stream to receive audio data from microphone
      _audioStreamController = StreamController<Uint8List>();
      
      // Start recording with specific parameters for pitch detection
      await _recorder!.startRecorder(
        toStream: _audioStreamController!.sink,
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 44100,
      );

      // Subscribe to audio data stream for real-time pitch analysis
      _recordingDataSubscription = _recorder!.onProgress!.listen((data) {
        if (data.decibels != null && data.decibels! > -40) {
          _updatePitchDetection(data);
        }
      });
    } catch (e) {
      print('Failed to start pitch detection: $e');
    }
  }

  /// Process audio data and update pitch detection results
  void _updatePitchDetection(RecordingDisposition data) {
    // This is a simplified pitch detection implementation
    // In a real app, you would use more sophisticated algorithms like FFT, autocorrelation, etc.
    
    if (data.decibels == null) return;

    // Simulate pitch detection (replace with actual implementation)
    final double volume = data.decibels!;
    _isVoiceDetected = volume > -30; // Voice activity detection threshold

    if (_isVoiceDetected && _expectedNote != null) {
      // Simulate pitch detection confidence
      _pitchConfidence = math.max(0.0, (volume + 40) / 40);
      
      // Add to history for smoothing
      _pitchHistory.add(_pitchConfidence);
      _confidenceHistory.add(_pitchConfidence);
      
      if (_pitchHistory.length > _historyLength) {
        _pitchHistory.removeAt(0);
        _confidenceHistory.removeAt(0);
      }
      
      // Calculate smoothed values
      _smoothedPitch = _pitchHistory.reduce((a, b) => a + b) / _pitchHistory.length;
      _smoothedConfidence = _confidenceHistory.reduce((a, b) => a + b) / _confidenceHistory.length;
      
      // Simulate note detection (in real implementation, convert frequency to note)
      if (_smoothedConfidence > _confidenceThreshold) {
        _currentDetectedNote = _expectedNote; // Simplified - assume correct for demo
        _isCorrect = true;
        
        // Update note correctness tracking
        _noteCorrectness[_currentNoteIndex] = true;
        _correctNotesCount++;
        
        // Trigger visual feedback
        _pulseController.forward().then((_) => _pulseController.reverse());
        _glowController.forward().then((_) => _glowController.reverse());
      } else {
        _isCorrect = false;
        _noteCorrectness[_currentNoteIndex] = false;
      }
      
      // Update adaptive detection parameters
      _calculateAdaptiveDetection();
    } else {
      _isCorrect = false;
      _pitchConfidence = 0.0;
    }

    // Update debug information
    _updateDebugInfo();
    
    // Perform component tests if enabled
    if (_testWienerFilter || _testVoiceActivityDetector || _testPitchSmoother) {
      _performComponentTests(data);
    }

    if (mounted) setState(() {});
  }

  /// Perform isolated component tests for debugging
  void _performComponentTests(RecordingDisposition data) {
    if (_testWienerFilter) {
      _testWienerFilterIsolated(data);
    }
    if (_testVoiceActivityDetector) {
      _testVADIsolated(data);
    }
    if (_testPitchSmoother) {
      // Test pitch smoothing algorithm
      final smoothingFactor = 0.3;
      final rawPitch = data.decibels ?? 0.0;
      _smoothedPitch = _smoothedPitch * (1 - smoothingFactor) + rawPitch * smoothingFactor;
      _componentStats['pitch_smoother'] = {
        'raw_pitch': rawPitch,
        'smoothed_pitch': _smoothedPitch,
        'smoothing_factor': smoothingFactor,
      };
    }
  }

  /// Test Wiener filter in isolation
  void _testWienerFilterIsolated(RecordingDisposition data) {
    // Simulate Wiener filter noise reduction
    final noisePower = 0.1;
    final signalPower = (data.decibels ?? 0.0) / 100.0;
    final wienerGain = signalPower / (signalPower + noisePower);
    final filteredSignal = (data.decibels ?? 0.0) * wienerGain;
    
    _componentStats['wiener_filter'] = {
      'input_signal': data.decibels ?? 0.0,
      'noise_power': noisePower,
      'signal_power': signalPower,
      'wiener_gain': wienerGain,
      'filtered_signal': filteredSignal,
    };
  }

  /// Test Voice Activity Detector in isolation
  void _testVADIsolated(RecordingDisposition data) {
    final threshold = -30.0;
    final volume = data.decibels ?? -100.0;
    final isVoiceActive = volume > threshold;
    final confidence = math.max(0.0, (volume - threshold) / (0 - threshold));
    
    _componentStats['vad'] = {
      'volume': volume,
      'threshold': threshold,
      'is_voice_active': isVoiceActive,
      'confidence': confidence,
    };
  }

  /// Update debug information display
  void _updateDebugInfo() {
    _debugInfo = '''
Voice: ${_isVoiceDetected ? 'Detected' : 'Silent'}
Expected: ${_expectedNote ?? 'None'}
Detected: ${_currentDetectedNote ?? 'None'}
Confidence: ${(_pitchConfidence * 100).toStringAsFixed(1)}%
Smoothed: ${(_smoothedConfidence * 100).toStringAsFixed(1)}%
Correct: ${_isCorrect ? 'Yes' : 'No'}
Sensitivity: ${(_detectionSensitivity * 100).toStringAsFixed(0)}%
Threshold: ${(_confidenceThreshold * 100).toStringAsFixed(0)}%
''';
  }

  /// Get performance metrics for display
  double _getProcessingLoad() {
    // Simulate processing load calculation
    return math.min(1.0, (_pitchHistory.length / _historyLength) * 0.8 + 0.2);
  }

  double _getMemoryUsage() {
    // Simulate memory usage calculation
    return math.min(1.0, (_componentStats.length / 10.0) * 0.6 + 0.3);
  }

  double _getSystemHealth() {
    final load = _getProcessingLoad();
    final memory = _getMemoryUsage();
    return 1.0 - ((load + memory) / 2.0);
  }

  Color _getHealthColor() {
    final health = _getSystemHealth();
    if (health > 0.7) return Colors.green;
    if (health > 0.4) return Colors.orange;
    return Colors.red;
  }

  /// Stop pitch detection and clean up resources
  void _stopPitchDetection() async {
    try {
      _recordingDataSubscription?.cancel();
      _recordingDataSubscription = null;
      
      if (_recorder != null && _recorder!.isRecording) {
        await _recorder!.stopRecorder();
      }
    } catch (e) {
      print('Error stopping pitch detection: $e');
    }
  }

  // ============================================================================
  // SCORE LOADING
  // ============================================================================

  /// Load the music score from the uploaded file
  void _loadScore() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check if file exists
      final file = File(widget.filePath);
      if (!await file.exists()) {
        throw Exception('File not found: ${widget.filePath}');
      }

      // Read and parse the MusicXML file
      final xmlString = await file.readAsString();
      final score = Score.fromXML(xmlString);
      
      setState(() {
        _scoreFuture = Future.value(score);
        _isLoading = false;
        
        // Set BPM to default value (score doesn't contain BPM information)
        // BPM is managed separately and can be adjusted by user
        
        // Count total playable notes for scoring
        _totalPlayableNotes = 0;
        for (final measure in score.measures) {
          for (final note in measure.notes) {
            if (!note.isRest) {
              _totalPlayableNotes++;
            }
          }
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load music file: $e';
        _isLoading = false;
      });
    }
  }

  // ============================================================================
  // EXERCISE CONTROL
  // ============================================================================

  /// Start the countdown before beginning the exercise
  void _startCountdown() {
    setState(() {
      _showCountdown = true;
      _countdown = 3;
      _isCountingIn = true;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
      });

      if (_countdown <= 0) {
        timer.cancel();
        setState(() {
          _showCountdown = false;
          _isCountingIn = false;
        });
        _startExercise();
      }
    });
  }

  /// Show settings dialog for exercise configuration
  void _showSettingsDialog() {
    // Use temporary variable so changes only apply when user confirms
    double tempBpm = _bpm.toDouble();
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
                                  _bpm = tempBpm.round();
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
                                  _bpm = tempBpm.round();
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
                              _bpm = value.round();
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
                          _bpm = tempBpm.round();
                          _isMaleSinger = tempIsMaleSinger;
                          // Update component stats collection
                          if (_showComponentStats) {
                            _updateComponentStats();
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

  /// Update component statistics for debugging
  void _updateComponentStats() {
    if (!_showComponentStats) return;
    
    _componentStats['pitch_detection'] = {
      'confidence': _pitchConfidence,
      'smoothed_confidence': _smoothedConfidence,
      'voice_detected': _isVoiceDetected,
      'expected_note': _expectedNote,
      'detected_note': _currentDetectedNote,
    };
    
    _componentStats['performance'] = {
      'processing_load': _getProcessingLoad(),
      'memory_usage': _getMemoryUsage(),
      'system_health': _getSystemHealth(),
    };
  }

  /// Build component statistics widgets for debug display
  List<Widget> _buildComponentStatsWidgets() {
    return _componentStats.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '${entry.key}: ${entry.value}',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      );
    }).toList();
  }

  Widget _buildPerformanceIndicator(String label, double value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
        const SizedBox(height: 2),
        Container(
          width: 30,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[700],
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // Cancel all timers
    _playbackTimer?.cancel();
    _countdownTimer?.cancel();
    _metronomeTimer?.cancel();
    
    // Dispose animation controllers
    _pulseController.dispose();
    _glowController.dispose();
    
    // Clean up audio resources
    _stopPitchDetection();
    _recorder?.closeRecorder();
    _metronomePlayer?.closePlayer();
    
    // Dispose scroll controller
    _noteScrollController.dispose();
    
    // Reset screen orientation to allow all orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    super.dispose();
  }

  // ============================================================================
  // EXERCISE PLAYBACK CONTROL
  // ============================================================================

  /// Start the main exercise playback
  void _startExercise() async {
    if (_scoreFuture == null) return;

    final score = await _scoreFuture!;
    
    // Build note positions cache for efficient lookup
    _buildNotePositions(score);
    
    setState(() {
      _isPlaying = true;
      _isPaused = false;
      _currentTime = 0.0;
      _currentNoteIndex = 0;
      _correctNotesCount = 0;
      _noteCorrectness.clear();
      _reachedEnd = false;
      _expectedNote = null;
      _currentDetectedNote = null;
      _isCorrect = false;
      _pitchConfidence = 0.0;
    });

    // Reset timing
    _elapsedBeforePauseSec = 0.0;
    _playbackStopwatch = Stopwatch()..start();

    // Start audio systems
    _startPitchDetection();
    if (_metronomeEnabled) {
      _startMetronome();
    }

    // Start the main playback timer
    _startPlaybackTimer(score);
  }

  /// Start the playback timer that drives the exercise progression
  void _startPlaybackTimer(Score score) {
    const updateInterval = Duration(milliseconds: 50); // 20 FPS for smooth updates
    
    _playbackTimer = Timer.periodic(updateInterval, (timer) {
      if (!_isPlaying || _isPaused) return;

      // Calculate current time based on stopwatch
      final elapsedMs = _playbackStopwatch?.elapsedMilliseconds ?? 0;
      _currentTime = _elapsedBeforePauseSec + (elapsedMs / 1000.0);

      _updatePlaybackState(score);
    });
  }

  /// Update the playback state including note progression and metronome
  void _updatePlaybackState(Score score) {
    setState(() {
      // Update metronome if enabled
      if (_metronomeEnabled) {
        _updateMetronome(score);
      }

      // Update current note and expected note
      _updateCurrentNote(score);
      
      // Scroll to current note in the note row
      _scrollToCurrentNote();
      
      // Update component statistics
      _updateComponentStats();
    });
  }

  /// Update metronome timing and trigger clicks
  void _updateMetronome(Score score) {
    // Calculate current beat position
    const double secondsPerMinute = 60.0;
    final int beatType = score.beatType;
    final double beatUnitSeconds = (secondsPerMinute / _bpm) * (4.0 / beatType);
    final double currentBeats = _currentTime / beatUnitSeconds;
    final int wholeBeat = currentBeats.floor();

    // Trigger metronome click on new beats
    if (wholeBeat != _lastWholeBeat && wholeBeat >= 0) {
      _lastWholeBeat = wholeBeat;
      
      // Determine if this is a downbeat (first beat of measure)
      final int beatsPerMeasure = score.beats;
      final bool isDownbeat = (wholeBeat % beatsPerMeasure) == 0;
      
      _triggerMetronome(downbeat: isDownbeat);
    }
  }

  /// Update the current note index and expected note
  void _updateCurrentNote(Score score) {
    // Calculate current beat position
    const double secondsPerMinute = 60.0;
    final int beatType = score.beatType;
    final double beatUnitSeconds = (secondsPerMinute / _bpm) * (4.0 / beatType);
    final double currentBeats = _currentTime / beatUnitSeconds;

    // Use binary search for efficient note lookup
    final newNoteIndex = _findCurrentNoteIndex(currentBeats);
    
    // Update expected/current note on index change
    if (!_isCountingIn && newNoteIndex != _currentNoteIndex) {
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
      
      // Show completion dialog
      Future.delayed(const Duration(milliseconds: 500), () {
        _showCompletionDialog();
      });
    }
  }

  /// Scroll the note row to keep current note visible
  void _scrollToCurrentNote() {
    if (_noteScrollController.hasClients && _currentNoteIndex < _noteNames.length) {
      const double noteWidth = 48.0; // 40 + 8 spacing
      final double targetOffset = _currentNoteIndex * noteWidth;
      final double maxOffset = _noteScrollController.position.maxScrollExtent;
      final double clampedOffset = math.min(targetOffset, maxOffset);
      
      _noteScrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Update the expected note based on current position
  void _updateExpectedNote(Score score) {
    int noteIndex = 0;
    for (final measure in score.measures) {
      for (final note in measure.notes) {
        if (!note.isRest) {
          if (noteIndex == _currentNoteIndex) {
            _expectedNote = '${note.step}${note.octave}';
            return;
          }
          noteIndex++;
        }
      }
    }
    _expectedNote = null;
  }

  /// Get the duration of a note in beats
  double _getNoteDuration(Note note) {
    // Convert note type to duration in beats
    switch (note.type) {
      case 'whole': return 4.0;
      case 'half': return 2.0;
      case 'quarter': return 1.0;
      case 'eighth': return 0.5;
      case 'sixteenth': return 0.25;
      default: return 1.0; // Default to quarter note
    }
  }

  /// Pause the exercise
  void _pauseExercise() {
    setState(() {
      _isPaused = true;
      _isPlaying = false;
    });
    
    // Store elapsed time before pause
    _elapsedBeforePauseSec = _currentTime;
    _playbackStopwatch?.stop();
    
    // Pause audio systems
    _stopPitchDetection();
    _stopMetronome();
    
    // Cancel playback timer
    _playbackTimer?.cancel();
  }

  /// Resume the exercise from pause
  void _resumeExercise() async {
    if (_scoreFuture == null) return;
    
    final score = await _scoreFuture!;
    
    setState(() {
      _isPlaying = true;
      _isPaused = false;
    });
    
    // Resume timing from where we left off
    _playbackStopwatch = Stopwatch()..start();
    
    // Resume audio systems
    _startPitchDetection();
    if (_metronomeEnabled) {
      _startMetronome();
    }
    
    // Resume playback timer
    _startPlaybackTimer(score);
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
      if (_metronomePlayer!.isOpen() && _metronomePlayer!.isPlaying) {
        if (immediate) {
          // Hard stop (pause/stop actions)
          _metronomePlayer!.stopPlayer();
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
      if (!_metronomePlayer!.isOpen()) {
        try { await _metronomePlayer!.openPlayer(); } catch (_) {}
        if (!_metronomePlayer!.isOpen()) {
          // Fallback if we still cannot open
          try { SystemSound.play(SystemSoundType.click); } catch (_) {}
          return;
        }
      }
      // Avoid cutting the click if it's still within its duration; otherwise, force stop to allow a new click
      if (_metronomePlayer!.isPlaying) {
        final int nowUs = DateTime.now().microsecondsSinceEpoch;
        final int elapsedMs = ((nowUs - _lastClickStartUs) / 1000).round();
        if (elapsedMs < _clickDurationMs - 5) {
          // Still in click window → skip retrigger to avoid cut
          return;
        }
        // Click should have finished by now but player still reports playing → stop to start the next
        try { await _metronomePlayer!.stopPlayer(); } catch (_) {}
      }
      final Uint8List data = _generateClickPcm(
        frequencyHz: downbeat ? 1400 : 1000,
        durationMs: _clickDurationMs,
        sampleRate: 44100,
        amplitude: downbeat ? 0.6 : 0.4,
      );
      _lastClickStartUs = DateTime.now().microsecondsSinceEpoch;
      try {
        await _metronomePlayer!.startPlayer(
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
          widget.fileName,
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
                          bpm: _bpm.toDouble(),
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
               child: const Text('Try Again'),
             ),
           ],
         );
       },
     );
   }

   /// Save practice session results to database for progress tracking
   void _savePracticeSession(int correct, int total, String percent) async {
     try {
       final dbHelper = DatabaseHelper();
       await dbHelper.insertPracticeSession({
         'fileName': widget.fileName,
         'filePath': widget.filePath,
         'correctNotes': correct,
         'totalNotes': total,
         'percentage': int.parse(percent),
         'bpm': _bpm,
         'singerGender': _singerGender,
         'timestamp': DateTime.now().millisecondsSinceEpoch,
       });
     } catch (e) {
       print('Failed to save practice session: $e');
     }
   }

   // ============================================================================
   // NOTE POSITION CACHING - Build and use cached note positions for performance
   // ============================================================================

   /// Build note positions cache for efficient note lookup during playback
   void _buildNotePositions(Score score) {
     if (_notePositions.isNotEmpty) return; // Already built

     _notePositions.clear();
     _noteNames.clear();
     
     double currentBeat = 0.0;
     
     for (final measure in score.measures) {
       for (final note in measure.notes) {
         if (!note.isRest) {
           _notePositions.add(currentBeat);
           _noteNames.add('${note.step}${note.octave}');
         }
         currentBeat += _getNoteDuration(note);
       }
     }
     
     _needsNoteListRebuild = false;
   }

   /// Find current note index using binary search for performance
   int _findCurrentNoteIndex(double currentBeats) {
     if (_notePositions.isEmpty) return 0;
     
     // Binary search for the current note
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