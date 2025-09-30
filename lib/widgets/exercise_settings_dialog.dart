import 'package:flutter/material.dart';

/// Settings dialog for exercise configuration
/// Handles BPM adjustment, singer gender settings, metronome controls, and debug controls
class ExerciseSettingsDialog extends StatefulWidget {
  final double initialBpm;
  final bool initialIsMaleSinger;
  final bool showDebugControls;
  final bool initialMetronomeEnabled;
  final int initialMetronomeVolume;
  final Function(double bpm, bool isMaleSinger, Map<String, bool> debugSettings, bool metronomeEnabled, int metronomeVolume) onSettingsChanged;

  const ExerciseSettingsDialog({
    super.key,
    required this.initialBpm,
    required this.initialIsMaleSinger,
    this.showDebugControls = false,
    this.initialMetronomeEnabled = false,
    this.initialMetronomeVolume = 70,
    required this.onSettingsChanged,
  });

  @override
  State<ExerciseSettingsDialog> createState() => _ExerciseSettingsDialogState();
}

class _ExerciseSettingsDialogState extends State<ExerciseSettingsDialog> {
  late double _tempBpm;
  late bool _tempIsMaleSinger;
  late bool _tempMetronomeEnabled;
  late int _tempMetronomeVolume;
  
  // Debug settings
  bool _showDebugPanel = false;
  bool _testWienerFilter = false;
  bool _testVoiceActivityDetector = false;
  bool _testPitchSmoother = false;
  bool _showComponentStats = false;

  @override
  void initState() {
    super.initState();
    _tempBpm = widget.initialBpm;
    _tempIsMaleSinger = widget.initialIsMaleSinger;
    _tempMetronomeEnabled = widget.initialMetronomeEnabled;
    _tempMetronomeVolume = widget.initialMetronomeVolume;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF8F4E1),
      child: Container(
        width: 400, // Fixed width
        height: MediaQuery.of(context).size.height * 0.85, // Use 85% of screen height
        padding: const EdgeInsets.all(14), // Reduced padding for more content space
        child: Column(
          children: [
            // Title
            const Text(
              'Exercise Settings',
              style: TextStyle(
                color: Color(0xFF543310),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10), // Reduced from 24
            
            // Scrollable content area
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildBpmSection(),
                    const SizedBox(height: 10), // Reduced from 24
                    _buildSingerGenderSection(),
                    const SizedBox(height: 10), // Reduced from 24
                    _buildMetronomeSection(),
                    if (widget.showDebugControls) ...[
                      const SizedBox(height: 10), // Reduced from 24
                      _buildDebugSection(),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 8), // Reduced from 16
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Reduced button padding
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF543310)),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final debugSettings = {
                      'showDebugPanel': _showDebugPanel,
                      'testWienerFilter': _testWienerFilter,
                      'testVoiceActivityDetector': _testVoiceActivityDetector,
                      'testPitchSmoother': _testPitchSmoother,
                      'showComponentStats': _showComponentStats,
                    };
                    widget.onSettingsChanged(_tempBpm, _tempIsMaleSinger, debugSettings, _tempMetronomeEnabled, _tempMetronomeVolume);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFAF8F6F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Reduced button padding
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build the BPM adjustment section
  Widget _buildBpmSection() {
    return Column(
      children: [
        const SizedBox(height: 8), // Reduced from 14
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), // Reduced vertical padding from 10 to 8
          decoration: BoxDecoration(
            color: const Color(0xFFF8F4E1),
            border: Border.all(color: const Color(0xFFAF8F6F), width: 1.0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, color: Color(0xFF543310)),
                onPressed: () {
                  if (_tempBpm > 40) {
                    setState(() {
                      _tempBpm = (_tempBpm - 1).clamp(40.0, 244.0);
                    });
                  }
                },
              ),
              const SizedBox(width: 16),
              Text(
                '${_tempBpm.round()} BPM',
                style: const TextStyle(
                  color: Color(0xFF543310),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.add, color: Color(0xFF543310)),
                onPressed: () {
                  if (_tempBpm < 244) {
                    setState(() {
                      _tempBpm = (_tempBpm + 1).clamp(40.0, 244.0);
                    });
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFFAF8F6F),
            inactiveTrackColor: const Color(0xFFAF8F6F).withOpacity(0.2),
            thumbColor: const Color(0xFFAF8F6F),
            overlayColor: const Color(0xFFAF8F6F).withOpacity(0.2),
            valueIndicatorColor: const Color(0xFFAF8F6F),
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
            value: _tempBpm,
            min: 40,
            max: 244,
            divisions: 204,
            label: '${_tempBpm.round()} BPM',
            onChanged: (value) {
              setState(() {
                _tempBpm = value;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '40 BPM',
              style: TextStyle(
                color: Color(0xFF543310),
                fontSize: 12,
              ),
            ),
            Text(
              '244 BPM',
              style: TextStyle(
                color: Color(0xFF543310),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Higher BPM = Faster Note Changes',
          style: TextStyle(
            color: Color(0xFF543310),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// Build the debug controls section
  Widget _buildDebugSection() {
    return Column(
      children: [
        const Text(
          'Debug Controls',
          style: TextStyle(
            color: Color(0xFF543310),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8), // Reduced from 12
        Container(
          padding: const EdgeInsets.all(10), // Reduced padding from 16 to 10
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFAF8F6F).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Show Debug Panel', style: TextStyle(color: Color(0xFF543310))),
                value: _showDebugPanel,
                onChanged: (value) {
                  setState(() {
                    _showDebugPanel = value;
                  });
                },
                activeColor: const Color(0xFFAF8F6F),
              ),
              SwitchListTile(
                title: const Text('Test Wiener Filter', style: TextStyle(color: Color(0xFF543310))),
                subtitle: const Text('Isolate noise reduction', style: TextStyle(color: Color(0xFF543310), fontSize: 12)),
                value: _testWienerFilter,
                onChanged: (value) {
                  setState(() {
                    _testWienerFilter = value;
                  });
                },
                activeColor: Colors.green,
              ),
              SwitchListTile(
                title: const Text('Test Voice Activity Detector', style: TextStyle(color: Color(0xFF543310))),
                subtitle: const Text('Isolate voice detection', style: TextStyle(color: Color(0xFF543310), fontSize: 12)),
                value: _testVoiceActivityDetector,
                onChanged: (value) {
                  setState(() {
                    _testVoiceActivityDetector = value;
                  });
                },
                activeColor: Colors.orange,
              ),
              SwitchListTile(
                title: const Text('Test Pitch Smoother', style: TextStyle(color: Color(0xFF543310))),
                subtitle: const Text('Isolate pitch smoothing', style: TextStyle(color: Color(0xFF543310), fontSize: 12)),
                value: _testPitchSmoother,
                onChanged: (value) {
                  setState(() {
                    _testPitchSmoother = value;
                  });
                },
                activeColor: Colors.purple,
              ),
              SwitchListTile(
                title: const Text('Show Component Stats', style: TextStyle(color: Color(0xFF543310))),
                subtitle: const Text('Display performance metrics', style: TextStyle(color: Color(0xFF543310), fontSize: 12)),
                value: _showComponentStats,
                onChanged: (value) {
                  setState(() {
                    _showComponentStats = value;
                  });
                },
                activeColor: Colors.cyan,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build the metronome controls section
  Widget _buildMetronomeSection() {
    return Column(
      children: [
        const Text(
          'Metronome Settings',
          style: TextStyle(
            color: Color(0xFF543310),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8), // Reduced from 12
        Container(
          padding: const EdgeInsets.all(8), // Reduced padding from 16 to 8
          decoration: BoxDecoration(
            color: const Color(0xFFF8F4E1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFAF8F6F),
              width: 1.0,
            ),
          ),
          child: Column(
            children: [
              // Metronome Enable/Disable
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _tempMetronomeEnabled ? Icons.music_note : Icons.music_off,
                        color: _tempMetronomeEnabled 
                            ? const Color(0xFFAF8F6F) 
                            : const Color(0xFF74512D),
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        _tempMetronomeEnabled ? 'Metronome On' : 'Metronome Off',
                        style: const TextStyle(
                          color: Color(0xFF543310),
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _tempMetronomeEnabled,
                    onChanged: (value) {
                      setState(() {
                        _tempMetronomeEnabled = value;
                      });
                    },
                    activeColor: const Color(0xFFAF8F6F),
                    inactiveThumbColor: const Color(0xFF74512D),
                    inactiveTrackColor: const Color(0xFF74512D).withOpacity(0.3),
                  ),
                ],
              ),
              
              
              if (_tempMetronomeEnabled) ...[
                const SizedBox(height: 20),
                const Divider(color: Color(0xFFAF8F6F)),
                const SizedBox(height: 20),
                
                // Volume Control
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Volume',
                          style: TextStyle(
                            color: Color(0xFF543310),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${_tempMetronomeVolume}%',
                          style: const TextStyle(
                            color: Color(0xFF543310),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFFAF8F6F),
                        inactiveTrackColor: const Color(0xFFAF8F6F).withOpacity(0.3),
                        thumbColor: const Color(0xFF74512D),
                        overlayColor: const Color(0xFF74512D).withOpacity(0.2),
                        trackHeight: 4.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                      ),
                      child: Slider(
                        value: _tempMetronomeVolume.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        onChanged: (value) {
                          setState(() {
                            _tempMetronomeVolume = value.round();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40, // Fixed height to prevent resizing
          child: Center(
            child: Text(
              _tempMetronomeEnabled
                  ? 'Metronome will help you keep time during exercises'
                  : 'Enable metronome for timing assistance',
              style: TextStyle(
                color: const Color(0xFF543310).withOpacity(0.7),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  /// Build the singer gender selection section
  Widget _buildSingerGenderSection() {
    return Column(
      children: [
        const Text(
          'Singer Gender',
          style: TextStyle(
            color: Color(0xFF543310),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), // Reduced vertical padding from 10 to 8
          decoration: BoxDecoration(
            color: const Color(0xFFF8F4E1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFAF8F6F),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _tempIsMaleSinger ? Icons.male : Icons.female,
                    color: _tempIsMaleSinger 
                        ? const Color(0xFFAF8F6F) 
                        : const Color(0xFF74512D),
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _tempIsMaleSinger ? 'Male Singer' : 'Female Singer',
                    style: const TextStyle(
                      color: Color(0xFF543310),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _tempIsMaleSinger,
                onChanged: (value) {
                  setState(() {
                    _tempIsMaleSinger = value;
                  });
                },
                activeColor: const Color(0xFFAF8F6F),
                inactiveThumbColor: const Color(0xFF74512D),
                inactiveTrackColor: const Color(0xFF74512D).withOpacity(0.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40, // Fixed height to prevent resizing
          child: Center(
            child: Text(
              _tempIsMaleSinger
                  ? 'Optimized for male vocal range (80-400 Hz)'
                  : 'Optimized for female vocal range (150-800 Hz)',
              style: TextStyle(
                color: const Color(0xFF543310).withOpacity(0.7),
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}