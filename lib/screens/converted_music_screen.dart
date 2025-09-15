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
import 'dart:io';


// ============================================================================
// CONVERTED MUSIC SCREEN - Practice with converted MusicXML pieces
// ============================================================================
// This screen handles:
// - Loading and displaying music scores from files
// - Playing sessions with adjustable BPM
// - Real-time pitch detection using microphone
// - Metronome functionality
// - Piece controls (play, pause, replay)
// - Score tracking and progress saving

class ConvertedMusicScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const ConvertedMusicScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<ConvertedMusicScreen> createState() => _ConvertedMusicScreenState();
}

class _ConvertedMusicScreenState extends State<ConvertedMusicScreen> with SingleTickerProviderStateMixin {
  // ============================================================================
  // STATE VARIABLES - Track the current state of the session
  // ============================================================================
  
  // Session Data & Loading
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
  
  // Exercise Settings
  double _bpm = 120.0;                            // Beats per minute (exercise speed)
  
  // Precise timing helpers
  Stopwatch? _playbackStopwatch;                  // High-precision stopwatch for playback
  double _elapsedBeforePauseSec = 0.0;            // Accumulated time before a pause
  
  // UI Controllers
  final ScrollController _noteScrollController = ScrollController(); // Scrolls note list
  
  // Web Audio unlock not used on non-web platforms

  @override
  void initState() {
    super.initState();
    
    // ============================================================================
    // INITIALIZATION - Set up the converted music screen when it first loads
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
  _metronomePlayer = FlutterSoundPlayer();
  try {
    await _metronomePlayer.openPlayer();
  } catch (e) {
    debugPrint("Failed to initialize metronome player: $e");
  }
}


  /// Web audio unlock function (not needed on mobile)
  Future<void> _unlockWebAudioIfNeeded() async { return; }

  // ============================================================================
  // PITCH DETECTION - Real-time audio analysis to detect sung/played notes
  // ============================================================================
  
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
      Timer? _throttleTimer;
      _audioStreamSubscription = _audioStreamController!.stream.listen((buffer) {
        // Only process audio when exercise is playing
        if (!_isPlaying) return;

        try {
          // Throttle processing to avoid overwhelming the system (80ms intervals)
          if (_throttleTimer?.isActive ?? false) return;
          _throttleTimer = Timer(const Duration(milliseconds: 80), () {});

          // Convert audio buffer to frequency using Yin algorithm
          final frequency = YinAlgorithm.detectPitch(buffer, 44100);
          if (frequency == null) return;
          
          // Convert frequency to musical note (e.g., A4, C5)
          final note = NoteUtils.frequencyToNote(frequency);
          if (!mounted) return;
          
          // Update the UI with detected note and check correctness
          setState(() {
            _currentDetectedNote = note;
            if (_expectedNote != null) {
              // Check if detected note matches what should be played
              _isCorrect = note == _expectedNote;
              
              // Track correctness for this specific note
              final bool? previous = _noteCorrectness[_currentNoteIndex];
              _noteCorrectness[_currentNoteIndex] = _isCorrect;
              
              // Increment score if this note is newly correct
              if (_isCorrect && previous != true) {
                _correctNotesCount++;
              }
              
              // Update visual feedback color (green for correct, red for incorrect)
              _glowColorAnimation = ColorTween(
                begin: Colors.transparent,
                end: _isCorrect 
                  ? Colors.green.withOpacity(0.5)
                  : Colors.red.withOpacity(0.5),
              ).animate(_pulseController);
            }
          });
        } catch (e) {
          print('Error in pitch detection: $e');
        }
      });
    } catch (e) {
      print('Error starting recorder: $e');
    }
  }

  void _stopPitchDetection() async {
    _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _audioStreamController?.close();
    _audioStreamController = null;
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

      // Load MusicXML from file instead of assets
      final file = File(widget.filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist: ${widget.filePath}');
      }
      
      final xmlString = await file.readAsString();
      final score = Score.fromXML(xmlString);
      
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
        _error = 'Failed to load music file: $e';
        _isLoading = false;
      });
    }
  }

  // ============================================================================
  // SESSION CONTROL - Start, pause, resume, and stop the session
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
                  'Note Speed Settings',
                  style: TextStyle(color: Color(0xFFF5F5DD)),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
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

  /// Begin playing the session after countdown finishes
  void _startExercise() {
    if (!mounted) return;
    
    // ============================================================================
    // SESSION STARTUP - Initialize all systems for session playback
    // ============================================================================
    
    // Cancel any existing timers to avoid conflicts
    _playbackTimer?.cancel();
    
    // Reset all session state variables
    setState(() {
      _isPlaying = true;                  // Exercise is now playing
      _isPaused = false;                  // Not paused
      _reachedEnd = false;                // Haven't reached the end yet
      _currentTime = 0.0;                 // Start at beginning (0 seconds)
      _currentNoteIndex = 0;              // Start with first note
      _noteCorrectness.clear();           // Clear previous exercise results
      _correctNotesCount = 0;             // Reset score counter
    });

    // ============================================================================
      // TIMING SYSTEM SETUP - Set up precise timing for session playback
  // ============================================================================
  
      // Reset timing variables for accurate playback
    _elapsedBeforePauseSec = 0.0;        // No time accumulated from pauses
    _playbackStopwatch?.stop();          // Stop any existing stopwatch
    _playbackStopwatch = Stopwatch()..start(); // Start fresh stopwatch

    // ============================================================================
    // SYSTEM INITIALIZATION - Start all required systems
    // ============================================================================
    
    // Set the first note that should be played
    _scoreFuture.then((score) {
      if (!mounted) return;
      _updateExpectedNote(score);
    });

    // Start listening to microphone for pitch detection
    _startPitchDetection();

    // Initialize metronome if it's enabled
    if (_metronomeEnabled) {
      _lastWholeBeat = -1; // Reset beat counter to align with next beat
    }

    // Get the score from the future
    _scoreFuture.then((score) {
      if (!mounted) return;
      
      // Start playback timer with dynamic BPM
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
            final double metronomeBeatUnitSec = (60.0 / _bpm) * (4.0 / (_timeSigBeatType?.toDouble() ?? 4.0));
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
            
            // Update expected/current note on index change or if not set yet (first note)
            if (newNoteIndex != _currentNoteIndex || _expectedNote == null) {
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

  void _updateExpectedNote(Score score) {
    // Find the current note in the score
    int totalNotes = 0;
    for (final measure in score.measures) {
      for (final note in measure.notes) {
        if (totalNotes == _currentNoteIndex && !note.isRest) {
          setState(() {
            _expectedNote = "${note.step}${note.octave}";
            _isCorrect = false;
            // Don't update _noteCorrectness here, only when we get a correct/incorrect result
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
    });

    // Resume metronome phase
    if (_metronomeEnabled) {
      _lastWholeBeat = -1;
    }

    // Ensure expected note is present when resuming (in case it was cleared)
    _scoreFuture.then((score) {
      if (!mounted) return;
      if (_expectedNote == null) {
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
            final double metronomeBeatUnitSec = (60.0 / _bpm) * (4.0 / (_timeSigBeatType?.toDouble() ?? 4.0));
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
            if (newNoteIndex != _currentNoteIndex || _expectedNote == null) {
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
    });
    _elapsedBeforePauseSec = 0.0;
    _playbackStopwatch?.stop();
    _playbackStopwatch = null;
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
        try {
          _metronomePlayer.stopPlayer();
        } catch (e) {}
      } else {
        // let current click finish naturally
      }
    }
  } catch (e) {}

  if (mounted) setState(() => _metronomeFlash = false);
}


  Future<void> _playMetronomeClick({bool downbeat = false}) async {
  try {
    // Ensure player is open
    if (!_metronomePlayer.isOpen()) {
      try {
        await _metronomePlayer.openPlayer();
      } catch (e) {
        // fallback system sound if player can't open
        try {
          SystemSound.play(SystemSoundType.click);
        } catch (_) {}
        return;
      }
    }

    // If already playing, check if we need to stop first
    if (_metronomePlayer.isPlaying) {
      final int nowUs = DateTime.now().microsecondsSinceEpoch;
      final int elapsedMs = ((nowUs - _lastClickStartUs) / 1000).round();
      if (elapsedMs < _clickDurationMs - 5) {
        return; // still playing, skip retrigger
      }
      try {
        await _metronomePlayer.stopPlayer();
      } catch (e) {}
    }

    // Generate PCM data for click
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
    } catch (e) {
      try {
        SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  } catch (e) {
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
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
      backgroundColor: const Color(0xFF1A1A1A), // Dark background for better contrast
      appBar: AppBar(
        backgroundColor: const Color(0xFF232B39),
        title: Text(widget.fileName),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFF5F5DD)),
      ),
      body: Stack(
        children: [
          // ============================================================================
          // MAIN CONTENT - The converted piece interface (music sheet, controls, etc.)
          // ============================================================================
          Center(
            child: _buildBody(),
          ),
          
          // ============================================================================
          // NAVIGATION & UI OVERLAYS - Back button, level indicator, score display
          // ============================================================================
          
          // Back button (top-left)
//           Positioned(
//             top: 8,
//             left: 8,
//             child: Container(
//               decoration: BoxDecoration(
//                 color: Colors.black.withOpacity(0.3), // Semi-transparent background
//                 borderRadius: BorderRadius.circular(12),
//               ),
//               child: IconButton(
//                 icon: const Icon(Icons.arrow_back, color: Color(0xFFF5F5DD), size: 28),
//                 onPressed: () => Navigator.of(context).pop(),
//                 padding: const EdgeInsets.all(😎,
//                 constraints: const BoxConstraints(),
//                 style: IconButton.styleFrom(
//                   backgroundColor: Colors.transparent,
//                 ),
//               ),
//             ),
//           ),
// //           Positioned(
//             top: 16,
//             left: 64,
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 😎,
//               decoration: BoxDecoration(
//                 color: Colors.black.withOpacity(0.3),
//                 borderRadius: BorderRadius.circular(12),
//               ),
//               child: Text(
//                 'Converted: ${widget.fileName}',
//                 style: const TextStyle(
//                   color: Color(0xFFF5F5DD),
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//             ),
//           ),
//           // Score indicator centered at top
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B4511).withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _totalPlayableNotes > 0
                      ? 'Score: $_correctNotesCount / $_totalPlayableNotes  (${((_correctNotesCount / _totalPlayableNotes) * 100).clamp(0, 100).toStringAsFixed(0)}%)'
                      : 'Score: 0 / 0 (0%)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (_showCountdown && _countdown > 0)
            Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Color(0xFF8B4511).withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _countdown.toString(),
                  style: const TextStyle(
                    color: Colors.white,
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
        ],
      ),
    );
  }

  // ============================================================================
  // BODY BUILDER - Main content area of the converted music screen
  // ============================================================================
  
  /// Build the main content area, handling loading, errors, and the session interface
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
        
        // Calculate total duration based on actual note durations (more precise than measures * measureDuration)
        _lastMeasurePosition = _calculateScoreDurationSeconds(score);
        _totalDuration = _lastMeasurePosition;

        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  
                  // ============================================================================
                  // MUSIC SHEET DISPLAY - The main visual area showing the musical notation
                  // ============================================================================
                  Flexible(
                    flex: 10, // Takes up most of the screen space
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, left: 20, right: 24, bottom: 7),
                      child: Container(
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F5DD), // White background for music sheet
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B4511).withOpacity(0.10), // Subtle shadow
                              blurRadius: 16,
                              spreadRadius: 1,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                        child: Align(
                          alignment: const Alignment(-0.15, 0.0), // Align to left side
                          child: MusicSheet(
                            score: score,                    // The music data to display
                            isPlaying: _isPlaying,           // Whether exercise is active
                            currentTime: _currentTime,       // Current position in exercise
                            currentNoteIndex: _currentNoteIndex, // Which note is current
                            bpm: _bpm,                      // Speed of the exercise
                            isCorrect: _isCorrect,           // Whether current note is correct
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ============================================================================
                  // NOTE PROGRESS ROW - Horizontal scrollable list showing all notes in order
                  // ============================================================================
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF181F2A), // Dark blue background
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFF5F5DD).withOpacity(0.10), // Subtle beige glow
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: _buildScrollableNoteRow(score), // Build the scrollable note list
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // ============================================================================
                  // CONTROL BUTTONS - Play, pause, metronome, and other exercise controls
                  // ============================================================================
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF232B39), // Dark blue button container
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withOpacity(0.13), // Blue accent shadow
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Previous Exercise Button (not yet implemented)
                          IconButton(
                            icon: const Icon(Icons.skip_previous, size: 28, color: Color(0xFFF5F5DD)),
                            tooltip: 'Previous Piece',
                            onPressed: () {
                              // TODO: Implement previous exercise
                            },
                          ),
                          
                          // Metronome Toggle Button
                          IconButton(
                            icon: Icon(
                              _metronomeEnabled ? Icons.music_note : Icons.music_note_outlined,
                              size: 26,
                              color: _metronomeEnabled ? Colors.lightBlueAccent : Color(0xFFF5F5DD),
                            ),
                            tooltip: 'Toggle Metronome',
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
                          
                          // Replay Button - Restart the current exercise
                          IconButton(
                            icon: const Icon(Icons.replay, size: 28, color: Color(0xFFF5F5DD)),
                            tooltip: 'Replay',
                            onPressed: () {
                              _stopExercise();
                              _startCountdown();
                            },
                          ),
                          
                          // Main Play/Pause Button - Controls exercise playback
                          IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause : 
                              _isPaused ? Icons.play_arrow : 
                              Icons.play_arrow,
                              size: 34,
                              color: Colors.white
                            ),
                            tooltip: _isPlaying ? 'Pause' : 
                                    _isPaused ? 'Resume' : 
                                    'Start',
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
                          
                          // Next Exercise Button (not yet implemented)
                          IconButton(
                            icon: const Icon(Icons.skip_next, size: 28, color: Color(0xFFF5F5DD)),
                            tooltip: 'Next Piece',
                            onPressed: () {
                              // TODO: Implement next exercise
                            },
                          ),
                          
                          // Settings Button - Open BPM adjustment dialog
                          IconButton(
                            icon: const Icon(Icons.settings, size: 26, color: Color(0xFFF5F5DD)),
                            tooltip: 'Settings',
                            onPressed: _showSettingsDialog,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
    // Extract all playable notes (excluding rests) from the score
    final notes = <String>[];
    for (final measure in score.measures) {
      for (final note in measure.notes) {
        if (!note.isRest) {
          notes.add("${note.step}${note.octave}"); // Combine note name and octave (e.g., "A4", "C5")
        }
      }
    }
    
    // Create horizontal scrollable list of notes
    return ListView.separated(
      controller: _noteScrollController,           // Controls scrolling behavior
      scrollDirection: Axis.horizontal,            // Scroll left/right
      itemCount: notes.length,                     // Total number of notes
      padding: const EdgeInsets.symmetric(horizontal: 18),
      separatorBuilder: (context, idx) => const SizedBox(width: 12), // Space between notes
      itemBuilder: (context, idx) {
        // Determine the current state of this note
        final isCurrentNote = idx == _currentNoteIndex;    // Is this the note being played now?
        final wasCorrect = _noteCorrectness[idx];          // Was this note played correctly before?
        
        // ============================================================================
        // NOTE COLOR LOGIC - Visual feedback based on note correctness
        // ============================================================================
        
        // Choose color based on note status:
        // - Current note: Green if correct, red if incorrect
        // - Past notes: Green if was correct, red if was incorrect  
        // - Future notes: White (neutral)
        Color noteColor;
        if (isCurrentNote) {
          noteColor = _isCorrect ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8);
        } else if (wasCorrect != null) {
          noteColor = wasCorrect ? Colors.green.withOpacity(0.8): Colors.red.withOpacity(0.8);
        } else {
          noteColor = Color(0xFFF5F5DD);
        }

        return Container(
          decoration: BoxDecoration(
            color: noteColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Color(0xFFF5F5DD).withOpacity(0.18),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Text(
            notes[idx],
            style: TextStyle(
              color: isCurrentNote || wasCorrect != null ? Color(0xFFF5F5DD) : const Color(0xFF8B4511),
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.1,
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
            'Session Complete',
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
        'level': widget.fileName,                 // Converted file name
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
}