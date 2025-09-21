import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:xml/xml.dart';

class Note {
  final String step;
  final int octave;
  final double duration;
  final bool isRest;
  final String type; // quarter, half, whole, etc.
  final bool hasStem;
  final String stemDirection; // up or down
  final List<Slur> slurs;
  final bool hasDot;
  final int? alter; // for sharps and flats
  final String? beamValue; // value for beam (begin, continue, end)
  final int? beamNumber; // beam number attribute
  
  // Properties to store slur positions
  double? slurStartX;
  double? slurStartY;
  double? slurEndX;
  double? slurEndY;

  Note({
    required this.step,
    required this.octave,
    required this.duration,
    this.isRest = false,
    this.type = 'quarter',
    this.hasStem = true,
    this.stemDirection = 'up',
    this.slurs = const [],
    this.hasDot = false,
    this.alter,
    this.beamValue,
    this.beamNumber,
    this.slurStartX,
    this.slurStartY,
    this.slurEndX,
    this.slurEndY,
  });

  factory Note.fromXmlElement(XmlElement noteElem) {
    // Check for grace notes and skip them if present
    if (noteElem.getElement('grace') != null) {
      return Note(
        step: '',
        octave: 0,
        duration: 0,
        isRest: true,
        type: 'grace',
      );
    }

    final isRest = noteElem.getElement('rest') != null;
    final duration = double.tryParse(noteElem.getElement('duration')?.text ?? '1') ?? 1.0;
    
    // Get note type with better fallback logic
    String type;
    final typeElem = noteElem.getElement('type');
    // Check for dots first as it affects type inference
    final hasDot = noteElem.findElements('dot').isNotEmpty;
    
    if (typeElem != null) {
      type = typeElem.text;
    } else {
      // Infer type from duration, accounting for dots
      // When a note is dotted, its written duration is 2/3 of its actual duration
      final baseDuration = hasDot ? (duration * 2/3) : duration;
      if (baseDuration >= 4) type = 'whole';
      else if (baseDuration >= 2) type = 'half';
      else if (baseDuration >= 1) type = 'quarter';
      else if (baseDuration >= 0.5) type = 'eighth';
      else type = '16th';
    }
    
    // Parse stem information
    final stem = noteElem.getElement('stem');
    final hasStem = stem != null && type != 'whole';
    final stemDirection = stem?.text ?? 'up';
    
    // Parse beam information
    String? beamValue;
    int? beamNumber;
    final beamElements = noteElem.findElements('beam');
    if (beamElements.isNotEmpty) {
      // Just use the first beam for simplicity (typically number="1")
      final beamElem = beamElements.first;
      
      // MusicXML beam values can be: begin, continue, end, forward hook, backward hook
      // We'll map these to our simplified: begin, continue, end
      final rawBeamValue = beamElem.text.trim().toLowerCase();
      
      if (rawBeamValue == 'begin') {
        beamValue = 'begin';
      } else if (rawBeamValue == 'continue') {
        beamValue = 'continue';
      } else if (rawBeamValue == 'end') {
        beamValue = 'end';
      } else if (rawBeamValue.contains('hook')) {
        // Handle hook beams (partial beams) as end beams
        beamValue = 'end';
      }
      
      beamNumber = int.tryParse(beamElem.getAttribute('number') ?? '1') ?? 1;
    }
    
    // Parse slurs with better error handling
    final slurs = <Slur>[];
    final notations = noteElem.getElement('notations');
    if (notations != null) {
      for (final slur in notations.findElements('slur')) {
        final type = slur.getAttribute('type') ?? 'start';
        final number = int.tryParse(slur.getAttribute('number') ?? '1') ?? 1;
        slurs.add(Slur(type: type, number: number));
      }
    }

    if (isRest) {
      return Note(
        step: '',
        octave: 0,
        duration: duration,
        isRest: true,
        type: type,
        hasStem: false,
        stemDirection: 'up',
        slurs: slurs,
        hasDot: hasDot,
      );
    }

    // Parse pitch with better error handling
    final pitchElem = noteElem.getElement('pitch');
    if (pitchElem == null) {
      // Handle unpitched notes (like percussion)
      return Note(
        step: '',
        octave: 4,
        duration: duration,
        isRest: true,
        type: type,
        hasStem: hasStem,
        stemDirection: stemDirection,
        slurs: slurs,
        hasDot: hasDot,
      );
    }

    final step = pitchElem.getElement('step')?.text ?? '';
    final octave = int.tryParse(pitchElem.getElement('octave')?.text ?? '4') ?? 4;
    
    // Parse accidentals
    int? alter;
    final alterElem = pitchElem.getElement('alter');
    if (alterElem != null) {
      alter = int.tryParse(alterElem.text);
    } else {
      // Check for accidental element outside pitch
      final accidental = noteElem.getElement('accidental');
      if (accidental != null) {
        switch (accidental.text) {
          case 'sharp': alter = 1; break;
          case 'flat': alter = -1; break;
          case 'natural': alter = 0; break;
          case 'double-sharp': alter = 2; break;
          case 'double-flat': alter = -2; break;
        }
      }
    }

    return Note(
      step: step,
      octave: octave,
      duration: duration,
      type: type,
      hasStem: hasStem,
      stemDirection: stemDirection,
      slurs: slurs,
      hasDot: hasDot,
      alter: alter,
      beamValue: beamValue,
      beamNumber: beamNumber,
    );
  }
}

class Slur {
  final String type; // start or stop
  final int number;

  Slur({
    required this.type,
    required this.number,
  });
}

class Measure {
  final List<Note> notes;

  Measure({required this.notes});

  factory Measure.fromXmlElement(XmlElement measureElem) {
    final notes = <Note>[];
    for (final noteElem in measureElem.findElements('note')) {
      notes.add(Note.fromXmlElement(noteElem));
    }
    return Measure(notes: notes);
  }
}

class Score {
  final List<Measure> measures;
  final int beats;
  final int beatType;
  final int keySharps;

  Score({
    required this.measures,
    required this.beats,
    required this.beatType,
    required this.keySharps,
  });

  factory Score.fromXML(String xmlString) {
    final xml = XmlDocument.parse(xmlString);
    final measures = <Measure>[];
    int beats = 4;
    int beatType = 4;
    int keySharps = 0;

    // Find time signature (first occurrence)
    final timeElement = xml.findAllElements('time').firstOrNull;
    if (timeElement != null) {
      beats = int.tryParse(timeElement.getElement('beats')?.text ?? '4') ?? 4;
      beatType = int.tryParse(timeElement.getElement('beat-type')?.text ?? '4') ?? 4;
    }

    // Find key signature (first occurrence)
    final keyElement = xml.findAllElements('key').firstOrNull;
    if (keyElement != null) {
      keySharps = int.tryParse(keyElement.getElement('fifths')?.text ?? '0') ?? 0;
    }

    // Parse measures
    for (final measureElem in xml.findAllElements('measure')) {
      measures.add(Measure.fromXmlElement(measureElem));
    }

    return Score(
      measures: measures,
      beats: beats,
      beatType: beatType,
      keySharps: keySharps,
    );
  }
}

class MusicService {
  static Future<Score> loadMusicXML(String level) async {
    try {
      // Load the MusicXML file from assets
      final String xmlString = await rootBundle.loadString('assets/$level.musicxml');
      // Parse the MusicXML string into a Score object
      final Score score = Score.fromXML(xmlString);
      return score;
    } catch (e) {
      print('Error loading MusicXML file: $e');
      rethrow;
    }
  }

  static List<String> getAvailableLevels() {
    return ['1', '2', '3'];
  }

  static String getLevelTitle(String level) {
    switch (level) {
      case '1':
        return 'Level 1 Exercise';
      case '2':
        return 'Level 2 Exercise';
      case '3':
        return 'Level 3 Exercise';
      default:
        return 'Unknown Level';
    }
  }
} 