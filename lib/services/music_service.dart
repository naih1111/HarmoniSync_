import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:xml/xml.dart';
import 'package:archive/archive.dart';

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
  final double? defaultX; // MusicXML default-x positioning
  
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
    this.defaultX,
    this.slurStartX,
    this.slurStartY,
    this.slurEndX,
    this.slurEndY,
  });

  factory Note.fromXmlElement(XmlElement noteElem) {
    // Parse default-x positioning from MusicXML
    final defaultX = double.tryParse(noteElem.getAttribute('default-x') ?? '');
    
    // Check for grace notes and skip them if present
    if (noteElem.getElement('grace') != null) {
      return Note(
        step: '',
        octave: 0,
        duration: 0,
        isRest: true,
        type: 'grace',
        defaultX: defaultX,
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
        defaultX: defaultX,
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
        defaultX: defaultX,
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
      defaultX: defaultX,
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
  static Future<Score> loadMusicXML(String level, {int exerciseIndex = 0}) async {
    try {
      String xmlString;
      
      final exerciseFiles = getExerciseFiles(level);
      if (exerciseIndex >= exerciseFiles.length) {
        throw Exception('Exercise index $exerciseIndex out of range for level $level');
      }
      
      final fileName = exerciseFiles[exerciseIndex];
      
      // Construct the correct asset path based on level
      String assetPath;
      if (level == '1') {
        assetPath = 'assets/lvl1 mxl/$fileName';
      } else {
        assetPath = 'assets/lvl $level mxl/$fileName';
      }
      
      if (fileName.endsWith('.mxl')) {
        // Handle MXL files (compressed MusicXML)
        xmlString = await _loadMXLFile(assetPath);
      } else {
        // Handle regular MusicXML files
        xmlString = await rootBundle.loadString(assetPath);
      }
      
      // Parse the MusicXML string into a Score object
      final Score score = Score.fromXML(xmlString);
      return score;
    } catch (e) {
      print('Error loading MusicXML file: $e');
      rethrow;
    }
  }

  static Future<String> _loadMXLFile(String assetPath) async {
    try {
      // Load the MXL file as bytes
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      
      // Decompress the MXL file (it's a ZIP archive)
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      
      // Look for the main MusicXML file in the archive
      // MXL files typically contain a META-INF/container.xml that points to the main file
      // But for simplicity, we'll look for common patterns
      ArchiveFile? musicXmlFile;
      
      // First, try to find container.xml to get the proper root file
      final containerFile = archive.files.firstWhere(
        (file) => file.name.toLowerCase().endsWith('container.xml'),
        orElse: () => throw Exception('No container.xml found in MXL file'),
      );
      
      if (containerFile.content != null) {
        final containerXml = utf8.decode(containerFile.content as List<int>);
        final containerDoc = XmlDocument.parse(containerXml);
        
        // Find the rootfile element
        final rootFileElement = containerDoc.findAllElements('rootfile').first;
        final rootFilePath = rootFileElement.getAttribute('full-path');
        
        if (rootFilePath != null) {
          musicXmlFile = archive.files.firstWhere(
            (file) => file.name == rootFilePath,
            orElse: () => throw Exception('Root file $rootFilePath not found in MXL archive'),
          );
        }
      }
      
      // Fallback: look for any .xml file if container approach fails
      if (musicXmlFile == null) {
        musicXmlFile = archive.files.firstWhere(
          (file) => file.name.toLowerCase().endsWith('.xml') && 
                   !file.name.toLowerCase().contains('container'),
          orElse: () => throw Exception('No MusicXML file found in MXL archive'),
        );
      }
      
      if (musicXmlFile.content == null) {
        throw Exception('MusicXML file content is null');
      }
      
      // Convert the content to string
      return utf8.decode(musicXmlFile.content as List<int>);
    } catch (e) {
      print('Error loading MXL file $assetPath: $e');
      rethrow;
    }
  }

  static List<String> getAvailableLevels() {
    return ['1', '2', '3'];
  }

  static String getLevelTitle(String level, {int exerciseIndex = 0}) {
    final exerciseNumber = exerciseIndex + 1;
    switch (level) {
      case '1':
        return 'Level 1 - Exercise $exerciseNumber';
      case '2':
        return 'Level 2 - Exercise $exerciseNumber';
      case '3':
        return 'Level 3 - Exercise $exerciseNumber';
      default:
        return 'Unknown Level';
    }
  }

  static List<String> getExerciseFiles(String level) {
    switch (level) {
      case '1':
        return [
          '1.musicxml',  // Original file first
          '2.2.musicxml',
          '2.3.musicxml',
          '2.4.musicxml',
          '2.5.musicxml',
          '2.6.musicxml',
        ];
      case '2':
        return [
          '2.musicxml',  // Original file first
          '2.14.musicxml',
          '2.15.musicxml',
          '2.21.musicxml',
          '2.23.musicxml',
          '2.24.musicxml',
        ];
      case '3':
        return [
          '3.musicxml',  // Original file first
          '13.57.musicxml',
          '13.59.musicxml',
          '13.60.musicxml',
          '13.61.musicxml',
          '13.65.musicxml',
        ];
      default:
        return [];
    }
  }

  static int getExerciseCount(String level) {
    return getExerciseFiles(level).length;
  }
}