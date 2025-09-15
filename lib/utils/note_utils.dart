import 'dart:math' as math;

class NoteUtils {
  // Complete note frequency mapping for multiple octaves
  static const Map<String, double> _noteFrequencies = {
    // Octave 2 (Low)
    'C2': 65.41, 'C#2': 69.30, 'D2': 73.42, 'D#2': 77.78, 'E2': 82.41, 'F2': 87.31, 'F#2': 92.50, 'G2': 98.00, 'G#2': 103.83, 'A2': 110.00, 'A#2': 116.54, 'B2': 123.47,
    
    // Octave 3 (Low-Mid)
    'C3': 130.81, 'C#3': 138.59, 'D3': 146.83, 'D#3': 155.56, 'E3': 164.81, 'F3': 174.61, 'F#3': 185.00, 'G3': 196.00, 'G#3': 207.65, 'A3': 220.00, 'A#3': 233.08, 'B3': 246.94,
    
    // Octave 4 (Middle - A4 = 440Hz reference)
    'C4': 261.63, 'C#4': 277.18, 'D4': 293.66, 'D#4': 311.13, 'E4': 329.63, 'F4': 349.23, 'F#4': 369.99, 'G4': 392.00, 'G#4': 415.30, 'A4': 440.00, 'A#4': 466.16, 'B4': 493.88,
    
    // Octave 5 (High-Mid)
    'C5': 523.25, 'C#5': 554.37, 'D5': 587.33, 'D#5': 622.25, 'E5': 659.25, 'F5': 698.46, 'F#5': 739.99, 'G5': 783.99, 'G#5': 830.61, 'A5': 880.00, 'A#5': 932.33, 'B5': 987.77,
    
    // Octave 6 (High)
    'C6': 1046.50, 'C#6': 1108.73, 'D6': 1174.66, 'D#6': 1244.51, 'E6': 1318.51, 'F6': 1396.91, 'F#6': 1479.98, 'G6': 1567.98, 'G#6': 1661.22, 'A6': 1760.00, 'A#6': 1864.66, 'B6': 1975.53,
    
    // Octave 7 (Very High)
    'C7': 2093.00, 'C#7': 2217.46, 'D7': 2349.32, 'D#7': 2489.02, 'E7': 2637.02, 'F7': 2793.83, 'F#7': 2959.96, 'G7': 3135.96, 'G#7': 3322.44, 'A7': 3520.00, 'A#7': 3729.31, 'B7': 3951.07,
  };

  // Note names without octave for easier comparison
  static const List<String> _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  
  // Semitone intervals for frequency calculation
  static const double _a4Frequency = 440.0; // A4 = 440Hz (concert pitch)
  static const int _a4MidiNote = 69; // MIDI note number for A4

  /// Convert frequency to musical note with enhanced accuracy
  static String frequencyToNote(double frequency) {
    if (frequency <= 0) return 'C4'; // Default fallback
    
    // Use MIDI note calculation for more accurate conversion
    final midiNote = 12 * math.log(frequency / _a4Frequency) / math.ln2 + _a4MidiNote;
    final roundedMidi = midiNote.round();
    
    // Convert MIDI note to note name
    final octave = (roundedMidi / 12).floor() - 1;
    final noteIndex = roundedMidi % 12;
    
    if (noteIndex < 0 || noteIndex >= _noteNames.length) {
      return 'C4'; // Fallback
    }
    
    final noteName = _noteNames[noteIndex];
    final noteString = '$noteName$octave';
    
    // Validate that the note exists in our frequency map
    if (_noteFrequencies.containsKey(noteString)) {
      return noteString;
    }
    
    // Fallback to closest note in our map
    return _findClosestNote(frequency);
  }

  /// Find the closest note using the frequency map
  static String _findClosestNote(double frequency) {
    double minDiff = double.infinity;
    String closestNote = 'C4';

    _noteFrequencies.forEach((note, noteFreq) {
      final diff = (frequency - noteFreq).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestNote = note;
      }
    });

    return closestNote;
  }

  /// Convert note to frequency
  static double noteToFrequency(String note) {
    return _noteFrequencies[note] ?? 261.63; // Default to C4
  }

  /// Get the octave number from a note string
  static int getOctave(String note) {
    final octaveMatch = RegExp(r'\d+').firstMatch(note);
    return octaveMatch != null ? int.parse(octaveMatch.group(0)!) : 4;
  }

  /// Get the note name without octave (e.g., "C4" -> "C")
  static String getNoteName(String note) {
    return note.replaceAll(RegExp(r'\d+'), '');
  }

  /// Check if two notes are the same (ignoring octave)
  static bool isSameNote(String note1, String note2) {
    return getNoteName(note1) == getNoteName(note2);
  }

  /// Get the semitone difference between two notes
  static int getSemitoneDifference(String note1, String note2) {
    final freq1 = noteToFrequency(note1);
    final freq2 = noteToFrequency(note2);
    return (12 * math.log(freq2 / freq1) / math.ln2).round();
  }

  /// Check if a note is within a specific octave range
  static bool isInOctaveRange(String note, int minOctave, int maxOctave) {
    final octave = getOctave(note);
    return octave >= minOctave && octave <= maxOctave;
  }

  /// Get all notes in a specific octave
  static List<String> getNotesInOctave(int octave) {
    return _noteNames.map((note) => '$note$octave').toList();
  }

  /// Check if a frequency is within typical singing range
  static bool isInSingingRange(double frequency, {bool isMale = true}) {
    if (isMale) {
      return frequency >= 80 && frequency <= 400; // Male vocal range
    } else {
      return frequency >= 150 && frequency <= 800; // Female vocal range
    }
  }

  /// Get confidence score based on how close frequency is to note
  static double getNoteConfidence(double frequency, String expectedNote) {
    final expectedFreq = noteToFrequency(expectedNote);
    final diff = (frequency - expectedFreq).abs();
    final percentDiff = diff / expectedFreq;
    
    // Higher confidence for smaller differences
    if (percentDiff < 0.01) return 1.0; // Within 1%
    if (percentDiff < 0.02) return 0.9; // Within 2%
    if (percentDiff < 0.05) return 0.8; // Within 5%
    if (percentDiff < 0.1) return 0.6;  // Within 10%
    if (percentDiff < 0.2) return 0.4;  // Within 20%
    return 0.1; // Very far off
  }

  /// Get the next note in the chromatic scale
  static String getNextNote(String note) {
    final noteName = getNoteName(note);
    final octave = getOctave(note);
    final currentIndex = _noteNames.indexOf(noteName);
    
    if (currentIndex == -1) return note; // Invalid note
    
    if (currentIndex == _noteNames.length - 1) {
      // Wrap to next octave
      return '${_noteNames[0]}${octave + 1}';
    } else {
      return '${_noteNames[currentIndex + 1]}$octave';
    }
  }

  /// Get the previous note in the chromatic scale
  static String getPreviousNote(String note) {
    final noteName = getNoteName(note);
    final octave = getOctave(note);
    final currentIndex = _noteNames.indexOf(noteName);
    
    if (currentIndex == -1) return note; // Invalid note
    
    if (currentIndex == 0) {
      // Wrap to previous octave
      return '${_noteNames[_noteNames.length - 1]}${octave - 1}';
    } else {
      return '${_noteNames[currentIndex - 1]}$octave';
    }
  }

  /// Get all available notes (for debugging)
  static List<String> getAllNotes() {
    return _noteFrequencies.keys.toList()..sort();
  }

  /// Check if a note string is valid
  static bool isValidNote(String note) {
    return _noteFrequencies.containsKey(note);
  }

  /// Get frequency range for a specific octave
  static Map<String, double> getOctaveFrequencies(int octave) {
    final octaveNotes = <String, double>{};
    _noteFrequencies.forEach((note, freq) {
      if (getOctave(note) == octave) {
        octaveNotes[note] = freq;
      }
    });
    return octaveNotes;
  }

  /// Calculate cents difference between two frequencies
  static double getCentsDifference(double freq1, double freq2) {
    return 1200 * math.log(freq2 / freq1) / math.ln2;
  }

  /// Check if two notes are enharmonic equivalents (same pitch, different names)
  static bool areEnharmonic(String note1, String note2) {
    return noteToFrequency(note1) == noteToFrequency(note2);
  }

  /// Get access to the note frequencies map
  static Map<String, double> get noteFrequencies => _noteFrequencies;
}
