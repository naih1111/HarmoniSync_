import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/music_service.dart';
import '../services/pitch_detection_service.dart';
import '../services/metronome_service.dart';
import '../widgets/music_sheet.dart';
import '../widgets/exercise_controls.dart';
import '../widgets/note_progress_row.dart';
import '../widgets/exercise_settings_dialog.dart';
import '../widgets/debug_panel.dart';
import '../database/database_helper.dart';

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
  double _currentTime = 0.0;              // Current position in exercise (seconds)
  final double _totalDuration = 0.0;      // Total length of exercise (seconds)
  double _lastMeasurePosition = 1;        // End position of last measure - will be calculated
 
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
 
  // Services
  late PitchDetectionService _pitchDetectionService;
  late MetronomeService _metronomeService;
 
  // Exercise Settings
  double _bpm = 120.0;                            // Beats per minute (exercise speed)
  bool _isMaleSinger = true;                      // Singer gender setting
 
  // Precise timing helpers
  Stopwatch? _playbackStopwatch;                  // High-precision stopwatch for playback
  double _elapsedBeforePauseSec = 0.0;            // Accumulated time before a pause
 
  // UI Controllers
  final ScrollController _noteScrollController = ScrollController(); // Scrolls note list
 
  // Cache for note positions to avoid recalculating every frame
  final List<double> _notePositions = [];
  final List<String> _noteNames = [];
  bool _needsNoteListRebuild = true;

  // Debug and visual feedback
  String _debugInfo = '';
  double _pitchConfidence = 0.0;
  final bool _isVoiceDetected = false;
  Map<String, dynamic> _componentStats = {};
  final bool _showDebugPanel = false;
  
  // Time signature tracking
  int? _timeSigBeats;
  int? _timeSigBeatType;
  
  // Metronome state
  bool _metronomeEnabled = false;
  final bool _metronomeFlash = false;
  int _lastWholeBeat = -1;
  
  // Note duration for adaptive detection
  double _currentNoteDuration = 1.0;

  @override
  void initState() {
    super.initState();
   
    // Force landscape orientation for better music sheet viewing
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
   
    // Load the music score for this exercise level
    _loadScore();
   
    // Initialize animation controller
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
   
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowColorAnimation = ColorTween(
      begin: Colors.transparent,
      end: Colors.green.withValues(alpha: 0.5),
    ).animate(_pulseController);

    // Initialize services
    _initializeServices();
   
    // Ensure BPM is within valid range
    _bpm = _bpm.clamp(40.0, 244.0);
  }

  /// Initialize pitch detection and metronome services
  Future<void> _initializeServices() async {
    _pitchDetectionService = PitchDetectionService();
    _metronomeService = MetronomeService();
    
    try {
      await _pitchDetectionService.initialize();
      await _metronomeService.initialize();
      
      // Set up callbacks
      _pitchDetectionService.onNoteDetected = _onNoteDetected;
      _pitchDetectionService.onDebugUpdate = _onDebugUpdate;
      _pitchDetectionService.onStatsUpdate = _onStatsUpdate;
      _metronomeService.onFlashUpdate = _onMetronomeFlash;
      
    } catch (e) {
        debugPrint('Error initializing services: $e');
      }
  }

  /// Handle note detection from pitch detection service
  void _onNoteDetected(String note, double confidence, bool isCorrect) {
    if (!mounted) return;
    
    setState(() {
      _currentDetectedNote = note;
      _pitchConfidence = confidence;
      _isCorrect = isCorrect;
      
      if (isCorrect) {
        final bool? previous = _noteCorrectness[_currentNoteIndex];
        _noteCorrectness[_currentNoteIndex] = true;
        if (previous != true) {
          _correctNotesCount++;
        }
      }
    });
  }

  /// Handle debug information updates
  void _onDebugUpdate(String debugInfo) {
    _debugInfo = debugInfo;
  }

  /// Handle statistics updates
  void _onStatsUpdate(Map<String, dynamic> stats) {
    _componentStats = stats;
  }

  /// Handle metronome flash updates
  void _onMetronomeFlash(bool isFlashing) {
    if (mounted) {
      setState(() {
        // Flash state is handled by the metronome service
      });
    }
  }



  @override
  void dispose() {
    _countdownTimer?.cancel();
    _playbackTimer?.cancel();
    _pulseController.dispose();
    _noteScrollController.dispose();
    _pitchDetectionService.dispose();
    _metronomeService.dispose();
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

    // Play one measure of metronome before starting countdown
    if (_metronomeEnabled && _metronomeService.isInitialized) {
      _scoreFuture.then((score) async {
        _metronomeService.setBPM(_bpm.round());
        _metronomeService.setTimeSignature(score.beats, score.beatType);
        
        // Wait for one measure to complete before starting countdown
        await _metronomeService.playOneMeasure();
        
        // Start the actual countdown after metronome measure
        _startActualCountdown();
      });
    } else {
      // Start countdown immediately if metronome is disabled
      _startActualCountdown();
    }
  }

  /// Start the actual 3-2-1 countdown after metronome measure
  void _startActualCountdown() {
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
    showDialog(
      context: context,
      builder: (context) => ExerciseSettingsDialog(
        initialBpm: _bpm,
        initialIsMaleSinger: _isMaleSinger,
        initialMetronomeEnabled: _metronomeEnabled,
        initialMetronomeVolume: _metronomeService.getVolume(),
        showDebugControls: false, // Hide debug controls
        onSettingsChanged: (bpm, isMaleSinger, debugSettings, metronomeEnabled, metronomeVolume) {
          setState(() {
            _bpm = bpm;
            _isMaleSinger = isMaleSinger;
            _metronomeEnabled = metronomeEnabled;
            
            // Update services with new settings
            _pitchDetectionService.updateSingerGender(isMaleSinger);
            _pitchDetectionService.updateBPM(bpm);
            _metronomeService.setVolume(metronomeVolume);
            _metronomeService.setEnabled(metronomeEnabled);
            
            // Update debug settings
            _pitchDetectionService.setDebugMode(
              testWiener: debugSettings['testWienerFilter'],
              testVAD: debugSettings['testVoiceActivityDetector'],
              testSmoother: debugSettings['testPitchSmoother'],
              showStats: debugSettings['showComponentStats'],
            );
            
            // Handle metronome state changes properly
            if (_metronomeService.isPlaying) {
              _metronomeService.stop(immediate: true);
            }
            
            // Restart exercise with new settings if currently playing
            if (_isPlaying) {
              _stopExercise();
              _startExercise();
            }
          });
        },
      ),
    );
  }



  /// Begin playing the exercise after countdown finishes
  void _startExercise() {
    if (!mounted) return;
   
    _playbackTimer?.cancel();
   
    setState(() {
      _isPlaying = true;
      _isPaused = false;
      _reachedEnd = false;
      _currentTime = 0.0;
      _currentNoteIndex = 0;
      _noteCorrectness.clear();
      _correctNotesCount = 0;
    });

    _notePositions.clear();
    _noteNames.clear();
 
    _elapsedBeforePauseSec = 0.0;
    _playbackStopwatch?.stop();
    _playbackStopwatch = Stopwatch()..start();
    
    // Reset metronome beat counter to ensure first beat aligns with first note
    _lastWholeBeat = -1;

    _scoreFuture.then((score) {
      if (!mounted) return;
      
      // Build note positions immediately
      _buildNotePositions(score);
      
      // Immediately set the first note as expected and highlight it
      _updateExpectedNote(score);
      _metronomeService.setTimeSignature(score.beats, score.beatType);
      
      // Trigger the first metronome beat immediately if enabled
      if (_metronomeEnabled && _metronomeService.isInitialized) {
        _metronomeService.setBPM(_bpm.round());
        _metronomeService.setTimeSignature(score.beats, score.beatType);
        _metronomeService.start();
        
        // Trigger the first downbeat immediately
        _lastWholeBeat = 0;
        _triggerMetronome(downbeat: true);
      }
      
      // Start pitch detection with the first expected note
      _pitchDetectionService.startDetection(_expectedNote);
    });

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
   
    // Calculate target beat with a small look-ahead to compensate for audio latency
    // This helps the metronome click sound to align better with the visual beat
    final double lookAheadSec = 0.03; // 30ms look-ahead to compensate for audio latency
    final double adjustedCurrentBeats = currentBeats + (lookAheadSec / metronomeBeatUnitSec);
    final int targetBeat = adjustedCurrentBeats.floor();
    
    const double clickDurationSec = 0.05; // 50ms
    
    // Process any beats that need to be triggered
    while (_lastWholeBeat < targetBeat) {
      _lastWholeBeat++;
      final int beatsPerMeasure = (_timeSigBeats ?? 4).clamp(1, 12);
      // Only trigger metronome at the start of each measure (downbeat only)
      final bool isDownbeat = ((_lastWholeBeat + 1) % beatsPerMeasure) == 1;
      final double beatStartSec = _lastWholeBeat * metronomeBeatUnitSec;
      
      // Only trigger if it's a downbeat and we're still within the valid playback range
      // Skip the first beat since it was already triggered in _startExercise
      if (isDownbeat && _lastWholeBeat > 0 && beatStartSec + clickDurationSec <= _lastMeasurePosition) {
        _triggerMetronome(downbeat: true);
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

  /// Calculate adaptive detection parameters based on BPM and note duration
  void _calculateAdaptiveDetection() {
    // This method is now handled by the PitchDetectionService
    // Update the service with current note duration
    _pitchDetectionService.updateNoteDuration(_currentNoteDuration);
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
    
    // Calculate the actual end position of the exercise based on score content
    _lastMeasurePosition = _calculateScoreDurationSeconds(score);
  }

  /// Calculate precise score duration in seconds by summing note durations (including rests)
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

  /// Stop pitch detection (delegated to service)
  void _stopPitchDetection() {
    _pitchDetectionService.stopDetection();
  }

  /// Stop metronome (delegated to service)
  void _stopMetronome() {
    _metronomeService.stop();
  }

  /// Trigger metronome click (delegated to service)
  void _triggerMetronome({required bool downbeat}) {
    _metronomeService.updateTiming(
      _currentTime / ((60.0 / _bpm) * (4.0 / (_timeSigBeatType?.toDouble() ?? 4.0))),
      (60.0 / _bpm) * (4.0 / (_timeSigBeatType?.toDouble() ?? 4.0)),
      _lastMeasurePosition,
    );
  }

  /// Show completion dialog with score and save results to database
  void _showCompletionDialog() {
    if (!mounted) return;
   
    // Calculate final score statistics
    final int total = _totalPlayableNotes;
    final int correct = _correctNotesCount.clamp(0, total);
    final String percent = total > 0
        ? ((correct / total) * 100).clamp(0, 100).toStringAsFixed(0)
        : '0';

    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing without saving
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: AlertDialog(
              backgroundColor: const Color(0xFFF8F4E1), // Light beige background to match settings
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Center(
                child: Text(
                  'Exercise Complete!',
                  style: TextStyle(
                    color: Color(0xFF543310), // Dark brown text to match settings
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  // Score display container with border styling like settings
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F4E1),
                      border: Border.all(color: const Color(0xFFAF8F6F), width: 2.0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Your Score',
                          style: TextStyle(
                            color: const Color(0xFF543310).withOpacity(0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$correct / $total',
                          style: const TextStyle(
                            color: Color(0xFF543310),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$percent%',
                          style: const TextStyle(
                            color: Color(0xFFAF8F6F), // Brown accent color
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Name input field with settings-style theming
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Player Name',
                        style: TextStyle(
                          color: Color(0xFF543310),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFAF8F6F).withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: TextField(
                          controller: nameController,
                          style: const TextStyle(
                            color: Color(0xFF543310),
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter your name',
                            hintStyle: TextStyle(
                              color: const Color(0xFF543310).withOpacity(0.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                // Cancel/Close button with settings theme
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFF543310),
                      fontSize: 16,
                    ),
                  ),
                ),
                // Save & Close button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAF8F6F).withOpacity(0.8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Please enter your name'),
                          backgroundColor: const Color(0xFF8B4513), // Brown error color
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    _savePracticeSession(correct, total, percent, name);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save & Close'),
                ),
                // Save & Replay button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAF8F6F), // Primary brown color
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Please enter your name'),
                          backgroundColor: const Color(0xFF8B4513), // Brown error color
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    _savePracticeSession(correct, total, percent, name);
                    Navigator.of(context).pop();
                    _stopExercise();
                    _startCountdown();
                  },
                  child: const Text('Save & Replay'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Save the completed practice session to the database
  Future<void> _savePracticeSession(int correctNotes, int totalNotes, String percentage, String playerName) async {
    try {
      print(' Saving practice session...');
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final duration = _currentTime;
     
      final session = {
        'level': widget.level,
        'score': correctNotes,
        'total_notes': totalNotes,
        'percentage': double.parse(percentage),
        'practice_date': date,
        'practice_time': time,
        'duration_seconds': duration,
        'player_name': playerName,
        'created_at': now.toIso8601String(),
      };

      print('🎯 Session data: $session');
      final dbHelper = DatabaseHelper();
      final id = await dbHelper.insertPracticeSession(session);
      print('🎯 Practice session saved with ID: $id');
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Practice session saved successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('❌ Error saving practice session: $e');
      debugPrint('Error saving practice session: $e');
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save practice session: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Build the main content area, handling loading, errors, and the exercise interface
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5F5DD)),
        ),
      );
    }

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
                backgroundColor: const Color(0xFFF5F5DD),
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

        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Music Sheet Display
                  Expanded(
                    flex: 5,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B4511).withValues(alpha: 0.1),
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
                 
                  // Note Progress Row
                  Container(
                    height: 50,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: NoteProgressRow(
                      score: score,
                      currentNoteIndex: _currentNoteIndex,
                      noteCorrectness: _noteCorrectness,
                      isCorrect: _isCorrect,
                      pitchConfidence: _pitchConfidence,
                      scrollController: _noteScrollController,
                    ),
                  ),
                 
                  const SizedBox(height: 1),
                 
                  // Control Buttons
                  ExerciseControls(
                    isPlaying: _isPlaying,
                    isPaused: _isPaused,
                    metronomeEnabled: _metronomeService.isEnabled,
                    onPlay: () {
                      if (_isPaused) {
                        _resumeExercise();
                      } else {
                        _startCountdown();
                      }
                    },
                    onPause: _pauseExercise,
                    onReplay: () {
                      _stopExercise();
                      _startCountdown();
                    },
                    onMetronomeToggle: () {
                      setState(() {
                        _metronomeEnabled = !_metronomeEnabled;
                      });
                      _metronomeService.setEnabled(_metronomeEnabled);
                      // Don't start metronome here - it will start during countdown
                      if (!_metronomeEnabled && _metronomeService.isPlaying) {
                        _metronomeService.stop(immediate: true);
                      }
                    },
                    onSettings: _showSettingsDialog,
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
          
          // Update pitch detection service with new expected note (without restarting)
          _pitchDetectionService.updateExpectedNote(_expectedNote);
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
    
    // Update pitch detection service with null expected note
    _pitchDetectionService.updateExpectedNote(_expectedNote);
  }

  void _pauseExercise() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
   
    _pitchDetectionService.stopDetection();
    _metronomeService.stop(immediate: true);
    
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
   
    _playbackTimer?.cancel();
   
    _pitchDetectionService.startDetection(_expectedNote);
   
    setState(() {
      _isPlaying = true;
      _isPaused = false;
    });

    // Resume metronome if enabled
    if (_metronomeEnabled && _metronomeService.isInitialized) {
      _metronomeService.resume();
    }

    _scoreFuture.then((score) {
      if (!mounted) return;
      if (_expectedNote == null) {
        _updateExpectedNote(score);
      }
    });

    _playbackStopwatch?.stop();
    _playbackStopwatch = Stopwatch()..start();

    _scoreFuture.then((score) {
      if (!mounted) return;
     
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
       
        _updatePlaybackState(score);
      });
    });
  }

  void _stopExercise() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _countdownTimer?.cancel();
   
    _pitchDetectionService.stopDetection();
    _metronomeService.stop(immediate: true);
   
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
   
    _notePositions.clear();
    _noteNames.clear();
    _needsNoteListRebuild = true;
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
                  color: const Color(0xFF8B4511).withValues(alpha: 0.7),
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
         
          // Debug Panel Overlay
          DebugPanel(
            isVisible: _showDebugPanel,
            debugInfo: _debugInfo,
            componentStats: _componentStats,
            testWienerFilter: false,
            testVoiceActivityDetector: false,
            testPitchSmoother: false,
            showComponentStats: false,
            currentDetectedNote: _currentDetectedNote,
            expectedNote: _expectedNote,
            pitchConfidence: _pitchConfidence,
            isVoiceDetected: _isVoiceDetected,
          ),

          // Metronome Flash Indicator
          if (_metronomeService.isEnabled && _isPlaying)
            Positioned(
              top: 16,
              right: 16,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: _metronomeService.isFlashing 
                      ? Colors.lightBlueAccent 
                      : const Color(0xFFF5F5DD).withValues(alpha: 0.24),
                  shape: BoxShape.circle,
                  boxShadow: _metronomeService.isFlashing
                      ? [
                          BoxShadow(
                            color: Colors.lightBlueAccent.withValues(alpha: 0.6),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : [],
                ),
              ),
            ),
        ],
      ),
    );
  }
}