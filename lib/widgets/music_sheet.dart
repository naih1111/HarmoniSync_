import 'package:flutter/material.dart';
import '../services/music_service.dart';
import '../utils/music_fonts.dart';
import 'dart:math' as math;
import 'dart:async';

class MusicSheet extends StatefulWidget {
  final Score score;
  final bool isPlaying;
  final double currentTime; // Current playback time in seconds
  final int currentNoteIndex;
  final double bpm; // Add BPM parameter
  final bool isCorrect; // Add isCorrect parameter

  const MusicSheet({
    super.key,
    required this.score,
    required this.bpm, // Make BPM required
    required this.isCorrect, // Make isCorrect required
    this.isPlaying = false,
    this.currentTime = 0.0,
    this.currentNoteIndex = 0,
  });

  @override
  State<MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends State<MusicSheet> with TickerProviderStateMixin {
  ScrollController? _scrollController;
  late AnimationController _highlightController;
  late AnimationController _scrollAnimationController;
  late Animation<double> _highlightAnimation;
  late Animation<Color?> _glowColorAnimation;
  late Animation<double> _scrollAnimation;
  double _currentX = 0.0;
  double _lastTargetX = 0.0;
  int _lastMeasure = -1;
  bool _isScrolling = false;
  Timer? _scrollTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    _scrollAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // Smooth scroll duration
    );
    
    _highlightAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _highlightController, curve: Curves.easeInOut),
    );
    
    _glowColorAnimation = ColorTween(
      begin: Colors.transparent,
      end: widget.isCorrect ? Colors.green.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.5),
    ).animate(_highlightController);
    
    _scrollAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scrollAnimationController, 
        curve: Curves.easeInOutCubic, // Smooth easing curve
      ),
    );
    
    _scrollAnimation.addListener(() {
      if (_scrollController != null && _scrollController!.hasClients) {
        final currentScroll = _scrollController!.offset;
        final targetScroll = _lastTargetX;
        final newScroll = currentScroll + (targetScroll - currentScroll) * _scrollAnimation.value;
        _scrollController!.jumpTo(newScroll);
      }
    });
    
    _scrollAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _isScrolling = false;
        _scrollAnimationController.reset();
      }
    });
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    _highlightController.dispose();
    _scrollAnimationController.dispose();
    _scrollTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(MusicSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentTime != oldWidget.currentTime || 
        widget.bpm != oldWidget.bpm ||
        widget.isCorrect != oldWidget.isCorrect) {
      _updateScrollPosition();
      // Update glow color when correctness changes
      _glowColorAnimation = ColorTween(
        begin: Colors.transparent,
        end: widget.isCorrect ? Colors.green.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.5),
      ).animate(_highlightController);
    }
  }

  void _updateScrollPosition() {
    // Throttle scroll updates to reduce lag
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 100), () {
      _performScrollUpdate();
    });
  }

  void _performScrollUpdate() {
    // Calculate the x position based on current time and BPM
    const double secondsPerMinute = 60.0;
    final double beatDuration = secondsPerMinute / widget.bpm;
    
    // Calculate which measure we should be showing based on current time
    final double currentBeats = widget.currentTime / beatDuration;
    final int currentMeasure = (currentBeats / widget.score.beats).floor();
    
    // Don't scroll if we're within 3 measures of the end
    if (currentMeasure >= widget.score.measures.length - 3) {
      return;
    }
    
    // Calculate the scroll position for the current measure with smoother transitions
    final double measureWidth = 155.0;
    final double beatsIntoMeasure = currentBeats % widget.score.beats;
    final double progressInMeasure = beatsIntoMeasure / widget.score.beats;
    
    // Smooth scrolling: interpolate between current and next measure
    final double baseX = currentMeasure * measureWidth;
    final double targetX = baseX + (progressInMeasure * measureWidth * 0.8); // 0.8 for smoother feel
    
    // Only scroll if the target position has changed significantly and we're not already scrolling
    if ((targetX - _lastTargetX).abs() > 10.0 && !_isScrolling) {
      _lastTargetX = targetX;
      _isScrolling = true;
      
      // Adjust animation duration based on distance for more natural feel
      final distance = (targetX - (_scrollController?.offset ?? 0)).abs();
      final duration = (distance / 200.0 * 600).clamp(200.0, 1000.0); // Scale duration with distance
      
      _scrollAnimationController.duration = Duration(milliseconds: duration.round());
      _scrollAnimationController.forward();
      
      // Update _currentX for the painter
      _currentX = targetX;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate total width needed for all measures
    final measureCount = widget.score.measures.length;
    final minMeasureWidth = 155.0;
    final totalWidth = (measureCount * minMeasureWidth) + 200.0;
    
    return SingleChildScrollView(
      controller: _scrollController ?? ScrollController(),
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(20),
        width: totalWidth,
        child: Stack(
          children: [
            // Static background layer - only repaints when score changes
            RepaintBoundary(
              child: CustomPaint(
                painter: MusicSheetBackgroundPainter(
                  score: widget.score,
                ),
                size: Size(totalWidth, 300),
              ),
            ),
            // Dynamic overlay layer - only repaints when playback state changes
            RepaintBoundary(
              child: CustomPaint(
                painter: MusicSheetOverlayPainter(
                  score: widget.score,
                  currentX: _currentX,
                  isPlaying: widget.isPlaying,
                  currentNoteIndex: widget.currentNoteIndex,
                  currentTime: widget.currentTime,
                  bpm: widget.bpm,
                  isCorrect: widget.isCorrect,
                ),
                size: Size(totalWidth, 300),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MusicSheetBackgroundPainter extends CustomPainter {
  final Score score;
  
  // Standard music engraving measurements
  static const double staffSpacing = 10.0;   // Space between staff lines
  static const double lineWidth = 1.2;      // Staff line thickness
  static const double noteSize = 24.0;      // Note head size
  static const double stemLength = 40.0;    // Standard stem length
  static const double beamSpacing = 8.0;    // Space between beams
  static const double ledgerLineLength = 16.0; // Length of ledger lines
  static const double measureWidth = 160.0;  // Width for each measure

  // Staff positioning
  static const double staffStartX = 80.0;   // Left margin for staff
  static const double staffStartY = 50.0;   // Top margin for staff
  static const double clefOffset = 85.0;     // Vertical offset for treble clef

  MusicSheetBackgroundPainter({
    required this.score,
  });

  // Map to store slur start positions by slur number
  final Map<int, Map<String, double>> _slurStartPositions = {};
  // Map to store notes involved in each slur
  final Map<int, List<Note>> _slurNotes = {};

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke;

    // Draw staff lines
    _drawStaff(canvas, size, paint);

    // Draw clef
    _drawClef(canvas, size, paint);

    // Draw key signature
    _drawKeySignature(canvas, size, paint);

    // Draw time signature
    _drawTimeSignature(canvas, size, paint);

    // Draw measures and notes WITHOUT highlighting
    _drawMeasures(canvas, size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! MusicSheetBackgroundPainter) return true;
    
    // Only repaint if the score itself changes
    return oldDelegate.score != score;
  }

  void _drawStaff(Canvas canvas, Size size, Paint paint) {
    final endX = size.width - 20.0;
    paint.strokeWidth = lineWidth;
    
    for (var i = 0; i < 5; i++) {
      final y = staffStartY + (i * staffSpacing);
      canvas.drawLine(
        Offset(staffStartX, y),
        Offset(endX, y),
        paint,
      );
    }
  }

  void _drawClef(Canvas canvas, Size size, Paint paint) {
    // G clef (treble clef) should curl around the G line (second line from bottom)
    final textPainter = TextPainter(
      text: TextSpan(
        text: BravuraFont.trebleClef,
        style: const TextStyle(
          fontFamily: 'Bravura',
          fontSize: 48,  // Further reduced size
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    // Position clef so it curls around the G line
    final gLineY = staffStartY + staffSpacing * 3; // Second line from bottom
    final clefY = gLineY - textPainter.height * 0.52; // Further lowered the clef
    textPainter.paint(canvas, Offset(staffStartX + 4, clefY)); // Moved further right with positive offset
  }

  void _drawKeySignature(Canvas canvas, Size size, Paint paint) {
    final sharps = score.keySharps > 0 ? score.keySharps : 0;
    final flats = score.keySharps < 0 ? -score.keySharps : 0;
    if (sharps == 0 && flats == 0) return;

    // Calculate base position aligned with time signature
    final baseY = staffStartY + staffSpacing * 1.5; // Align with top number of time signature

    final sharpPositions = [
      baseY + staffSpacing * -1.5,   // F# (top line)
      baseY + staffSpacing * -0.5,   // C# (third space)
      baseY + staffSpacing * 2.0,    // G#
      baseY + staffSpacing * -0.0,   // D#
      baseY + staffSpacing * 3.0,    // A#
      baseY + staffSpacing * 0.5,    // E#
      baseY + staffSpacing * -1.0,   // B#
    ];
    final flatPositions = [
      baseY + staffSpacing * 0.5,    // Bb (middle line)
      baseY + staffSpacing * 3.0,    // Eb
      baseY + staffSpacing * 0.0,    // Ab
      baseY + staffSpacing * 2.5,    // Db
      baseY + staffSpacing * -0.5,   // Gb
      baseY + staffSpacing * 2.0,    // Cb
      baseY + staffSpacing * -1.0,   // Fb
    ];
    // Move first sharp closer to clef
    double x = staffStartX + 38; // Reduced from 48 for tighter placement
    final accidentalSpacing = 10.0; // Tighter spacing
    if (sharps > 0) {
      for (int i = 0; i < sharps && i < sharpPositions.length; i++) {
        double y = sharpPositions[i];
        double xOffset = 0.0;
        if (sharps > 1) {
          if (i == 0) {
            y = sharpPositions[1] - 14.0;
            xOffset = 4.0;
          } else if (i == 1) {
            y -= 8.0;
            xOffset = 4.0;
          }
        }
        _drawKeySignatureAccidental(canvas, x + xOffset, y, 1, paint);
        if (sharps == 2 && i == 0) {
          x += 7.0;
        } else {
          x += accidentalSpacing;
        }
      }
    } else if (flats > 0) {
      for (int i = 0; i < flats && i < flatPositions.length; i++) {
        _drawKeySignatureAccidental(canvas, x, flatPositions[i], -1, paint);
        x += accidentalSpacing;
      }
    }
  }

  void _drawKeySignatureAccidental(Canvas canvas, double x, double y, int alter, Paint paint) {
    final text = alter == 1 ? BravuraFont.accidentalSharp :
                alter == -1 ? BravuraFont.accidentalFlat :
                BravuraFont.accidentalNatural;
    final fontSize = noteSize * 1.13; // Larger for key signature
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Bravura',
          fontSize: fontSize,
          height: 1.0,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    // Center accidental horizontally and vertically on the staff line/space
    final accX = x - textPainter.width / 2 + 2; // +2 for a more engraved look
    final accY = y - textPainter.height / 2 + (alter == 1 ? 0.5 : (alter == -1 ? 0.0 : 0.0));
    canvas.save();
    // Slight rotation for engraving style
    canvas.translate(accX + textPainter.width/2, accY + textPainter.height/2);
    canvas.rotate(alter == 1 ? 0.01 : (alter == -1 ? -0.01 : 0.0));
    canvas.translate(-(accX + textPainter.width/2), -(accY + textPainter.height/2));
    textPainter.paint(canvas, Offset(accX, accY));
    canvas.restore();
  }

  void _drawTimeSignature(Canvas canvas, Size size, Paint paint) {
    final beatsText = BravuraFont.getTimeSignature(score.beats);
    final beatTypeText = BravuraFont.getTimeSignature(score.beatType);
    
    // Draw numerator (top number)
    final numeratorPainter = TextPainter(
      text: TextSpan(
        text: beatsText,
        style: const TextStyle(
          fontFamily: 'Bravura',
          fontSize: 36,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    numeratorPainter.layout();
    
    // Draw denominator (bottom number)
    final denominatorPainter = TextPainter(
      text: TextSpan(
        text: beatTypeText,
        style: const TextStyle(
          fontFamily: 'Bravura',
          fontSize: 36,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    denominatorPainter.layout();
    
    // Position time signature after clef with proper spacing
    final timeX = staffStartX + 65;
    
    // Center the numbers vertically in the staff
    final staffCenterY = staffStartY + (staffSpacing * 2);
    final totalHeight = numeratorPainter.height + denominatorPainter.height;
    final spacing = -120.0; // Dramatically increased overlap (10x tighter)
    
    // Calculate Y positions to center the entire time signature in the staff
    final numeratorY = staffCenterY - (totalHeight + spacing) / 2;
    final denominatorY = numeratorY + numeratorPainter.height + spacing;
    
    // Draw the numbers
    numeratorPainter.paint(canvas, Offset(timeX, numeratorY));
    denominatorPainter.paint(canvas, Offset(timeX, denominatorY));
  }

  void _drawMeasures(Canvas canvas, Size size, Paint paint) {
    // Clear slur tracking at start of drawing
    _slurStartPositions.clear();
    _slurNotes.clear();

    final staffHeight = staffSpacing * 4;
    final measureCount = score.measures.length;
    final totalWidth = size.width - 180.0;
    
    // Calculate measure widths based on note content
    List<double> measureWidths = [];
    
    // First pass: analyze measures to determine appropriate widths
    for (int m = 0; m < measureCount; m++) {
      final measure = score.measures[m];
      final noteCount = measure.notes.length;
      double width = 160.0; // Base minimum width
      
      // For measures with many eighth notes, increase the width
      final eighthNotes = measure.notes.where((n) => 
        n.type == 'eighth' || n.type == '16th'
      ).length;
      
      // Adjust width based on note count and types
      if (noteCount >= 6) {
        width += 40.0; // Add extra space for measures with many notes
      }
      if (eighthNotes >= 4) {
        width += eighthNotes * 5.0; // Extra space for each eighth note
      }
      
      // Make sure width is in reasonable range
      width = width.clamp(160.0, 240.0);
      measureWidths.add(width);
    }
    
    // Adjust total if needed to fit available space
    final requestedTotalWidth = measureWidths.reduce((a, b) => a + b);
    final scaleFactor = (totalWidth / requestedTotalWidth).clamp(0.85, 1.2);
    for (int i = 0; i < measureWidths.length; i++) {
      measureWidths[i] *= scaleFactor;
    }
    
    double currentX = staffStartX + 80.0;

    // First pass: collect all notes involved in slurs
    for (int m = 0; m < measureCount; m++) {
      final measure = score.measures[m];
      for (final note in measure.notes) {
        for (final slur in note.slurs) {
          if (slur.type == 'start') {
            _slurNotes[slur.number] = [note];
          } else if (slur.type == 'stop') {
            if (_slurNotes.containsKey(slur.number)) {
              _slurNotes[slur.number]!.add(note);
            }
          }
        }
      }
    }

    for (int m = 0; m < measureCount; m++) {
      final measure = score.measures[m];
      final measureWidth = measureWidths[m];
      
      // Draw barline
      canvas.drawLine(
        Offset(currentX, staffStartY - 2),
        Offset(currentX, staffStartY + staffHeight + 2),
        paint..strokeWidth = lineWidth,
      );

      // Calculate note spacing within measure
      final noteCount = measure.notes.length;
      double noteSpacing = measureWidth / (noteCount + 1);
      
      // Adjust spacing based on note types
      if (noteCount > 1) {
        final longNotes = measure.notes.where((n) => 
          n.type == 'whole' || 
          n.type == 'half' || 
          (n.type == 'quarter' && n.hasDot)
        ).length;
        final shortNotes = noteCount - longNotes;
        
        // Base spacing calculation
        noteSpacing = ((measureWidth - 60) / (noteCount + 0.5)).clamp(30.0, 75.0);
        
        // Adjustments based on note types
        if (longNotes > 0) noteSpacing += 8.0;
        if (shortNotes > 2) noteSpacing -= 4.0;
        if (shortNotes > 4) noteSpacing -= 2.0;
        
        // Special case for all eighth notes (like measure 4)
        if (shortNotes == noteCount && noteCount >= 6) {
          noteSpacing = (measureWidth - 50) / (noteCount + 0.5);
        }
      }

      // Identify beam groups based on MusicXML beam information
      final List<List<int>> beamGroups = [];
      final Map<int, List<int>> beamGroupsByNumber = {}; // Group by beam number
      
      for (int i = 0; i < measure.notes.length; i++) {
        final note = measure.notes[i];
        
        // Skip if note is a rest
        if (note.isRest) continue;
        
        // Check for beam information
        if (note.beamValue != null) {
          final beamNumber = note.beamNumber ?? 1;
          
          // Start a new beam group if this is the beginning
          if (note.beamValue == 'begin') {
            if (!beamGroupsByNumber.containsKey(beamNumber)) {
              beamGroupsByNumber[beamNumber] = [];
            }
            beamGroupsByNumber[beamNumber]!.add(i);
          }
          // Continue an existing beam group
          else if (note.beamValue == 'continue') {
            if (beamGroupsByNumber.containsKey(beamNumber)) {
              beamGroupsByNumber[beamNumber]!.add(i);
            }
          }
          // End a beam group
          else if (note.beamValue == 'end') {
            if (beamGroupsByNumber.containsKey(beamNumber)) {
              beamGroupsByNumber[beamNumber]!.add(i);
              
              // Finalize the beam group if it has at least 2 notes
              if (beamGroupsByNumber[beamNumber]!.length >= 2) {
                beamGroups.add(List.from(beamGroupsByNumber[beamNumber]!));
              }
              beamGroupsByNumber.remove(beamNumber);
            }
          }
        }
      }
      
      // Fallback: If no beam info in MusicXML, use automatic grouping for consecutive eighth notes
      if (beamGroups.isEmpty) {
        List<int> currentGroup = [];
        
        for (int i = 0; i < measure.notes.length; i++) {
          final note = measure.notes[i];
          if ((note.type == 'eighth' || note.type == '16th') && !note.isRest) {
            currentGroup.add(i);
          } else {
            if (currentGroup.length >= 2) {
              beamGroups.add(List.from(currentGroup));
            }
            currentGroup = [];
          }
        }
        
        // Add the last group if it exists
        if (currentGroup.length >= 2) {
          beamGroups.add(List.from(currentGroup));
        }
      }

      // Draw notes
      double noteX = currentX + 25.0;
      
      // Adjust starting position for measures with many notes
      if (measure.notes.length >= 6) {
        noteX = currentX + 20.0; // Smaller initial margin for crowded measures
      }
      
      final List<Map<String, dynamic>> notePositions = [];
      
      for (int i = 0; i < measure.notes.length; i++) {
        final note = measure.notes[i];
        final noteY = _getNoteY(note, staffStartY);
        
        // Store position for beaming
        notePositions.add({
          'x': noteX,
          'y': noteY,
          'note': note,
          'index': i,
          'measureIndex': m,
        });
        
        // Draw ledger lines if needed (skip for rests)
        if (!note.isRest) {
          _drawLedgerLines(canvas, noteX, noteY, staffStartY, paint);
        }
        
        // Draw accidentals
        if (note.alter != null && note.alter != 0) {
          // Only show accidental if not covered by key signature
          if (!_isAccidentalInKeySignature(note)) {
            _drawAccidental(canvas, noteX - 20, noteY, note.alter!, paint);
          }
        } else if (note.alter == 0) {
          // Show natural if the note is sharped/flatted in the key signature
          if (_isAccidentalInKeySignature(note)) {
            _drawAccidental(canvas, noteX - 20, noteY, 0, paint);
          }
        }
        
        if (note.isRest) {
          // For rests, ignore the noteY value - they have standardized positions
          _drawRest(canvas, noteX, 0, note, paint); // The y value (0) will be ignored by _drawRest
        } else {
          // Draw note components in correct order
          _drawNoteHead(canvas, noteX, noteY, note, paint, m, i);
          
          if (_hasStem(note.type)) {
            _drawStem(canvas, noteX, noteY, note, paint);
          }
          
          // Only draw flags for notes that aren't part of beam groups
          bool isBeamed = false;
          for (final group in beamGroups) {
            if (group.contains(i)) {
              isBeamed = true;
              break;
            }
          }
          
          if (_hasFlag(note.type) && !isBeamed) {
            _drawFlag(canvas, noteX, noteY, note, paint);
          }
          
          if (note.hasDot) {
            // Check if the note is on a staff line
            bool isOnStaffLine = false;
            final staffTop = staffStartY;
            final staffBottom = staffStartY + (staffSpacing * 4);
            
            // Notes on staff lines have Y positions that align with staff lines
            for (int j = 0; j <= 4; j++) {
              double staffLineY = staffStartY + (j * staffSpacing);
              if ((noteY - staffLineY).abs() < 1.5) {
                isOnStaffLine = true;
                break;
              }
            }
            
            // Adjust dot position - move up if note is on a line
            double dotY = noteY;
            if (isOnStaffLine) {
              dotY -= staffSpacing / 2; // Move dot up to the space above
            }
            
            _drawDot(canvas, noteX + noteSize/2 - 2, dotY, paint);
          }
        }
        
        // Draw slurs if present
        if (note.slurs.isNotEmpty) {
          _drawSlurs(canvas, noteX, noteY, note, paint);
        }
        
        noteX += noteSpacing;
      }
      
      // Draw beams for eighth note groups
      for (final group in beamGroups) {
        _drawBeam(canvas, notePositions, group, paint);
      }

      // Calculate final X position for next measure
      // If last note would extend too close to or beyond the measure boundary,
      // adjust the measure width
      if (notePositions.isNotEmpty) {
        final lastNoteX = notePositions.last['x'];
        final minEndMargin = 30.0; // Minimum space after last note
        
        // Ensure the measure ends at least minEndMargin after the last note
        double suggestedNextX = lastNoteX + minEndMargin;
        double plannedNextX = currentX + measureWidth;
        
        // If needed, expand the measure to avoid crowding
        if (suggestedNextX > plannedNextX) {
          currentX = suggestedNextX;
        } else {
          currentX += measureWidth;
        }
      } else {
        currentX += measureWidth;
      }
    }

    // Final double barline
    canvas.drawLine(
      Offset(currentX, staffStartY - 2),
      Offset(currentX, staffStartY + staffHeight + 2),
      paint..strokeWidth = lineWidth,
    );
    canvas.drawLine(
      Offset(currentX + 4, staffStartY - 2),
      Offset(currentX + 4, staffStartY + staffHeight + 2),
      paint..strokeWidth = lineWidth * 2,
    );
  }

  void _drawNoteHead(Canvas canvas, double x, double y, Note note, Paint paint, int measureIndex, int noteIndex) {
    final text = note.type == 'whole' ? BravuraFont.noteheadWhole :
                note.type == 'half' ? BravuraFont.noteheadHalf :
                BravuraFont.noteheadBlack;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Bravura',
          fontSize: noteSize * (note.type == 'whole' || note.type == 'half' ? 1.05 : 1.0),
          height: 1.0,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    // For quarter notes, check if stem should be down (p-shape) and adjust position
    bool shouldAdjustForStem = false;
    if (note.type == 'quarter') {
      final middleLineY = staffStartY + (staffSpacing * 2);
      final stemDown = note.stemDirection == 'down' || 
                      (note.stemDirection != 'up' && y < middleLineY);
      shouldAdjustForStem = stemDown;
    }
    
    // Calculate position - center the notehead on the staff line or space
    double noteX;
    if (shouldAdjustForStem) {
      noteX = x - textPainter.width / 2;
    } else {
      noteX = x - textPainter.width / 2;
    }
    final noteY = y - textPainter.height / 2;

    // For half and whole notes, ensure crisp edges with proper stroke width
    if (note.type == 'half' || note.type == 'whole') {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = lineWidth * 1.2;
    } else {
      paint.style = PaintingStyle.fill;
    }
    
    textPainter.paint(canvas, Offset(noteX, noteY));
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

  bool _hasStem(String type) {
    return type != 'whole';
  }

  bool _hasFlag(String type) {
    return type == 'eighth' || type == '16th' || type == '32nd';
  }

  void _drawStem(Canvas canvas, double x, double y, Note note, Paint paint) {
    // Only modify stem direction for quarter notes
    // For other note types, use the explicit direction or calculate based on position
    final middleLineY = staffStartY + (staffSpacing * 2);
    
    bool stemUp;
    if (note.stemDirection == 'up') {
      stemUp = true;
    } else if (note.stemDirection == 'down') {
      stemUp = false;
    } else if (note.type == 'quarter') {
      // For quarter notes: above middle line = stem down, below = stem up
      stemUp = y >= middleLineY;
    } else {
      // Default for other notes: use explicit direction from MusicXML or calculate
      stemUp = note.stemDirection == 'up' || (note.stemDirection != 'down' && y >= middleLineY);
    }
    
    final stemPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = lineWidth * 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    double actualStemLength = stemLength * 0.65;
    
    if (y < staffStartY - staffSpacing * 1.5 || y > staffStartY + staffSpacing * 5.5) {
      actualStemLength += staffSpacing * 0.5;
    }
    
    if (stemUp) {
      // Stem up - positioned on the right side of the note head
      canvas.drawLine(
        Offset(x + noteSize/9.0, y - noteSize/9),
        Offset(x + noteSize/9.0, y - actualStemLength),
        stemPaint,
      );
    } else {
      // Stem down - make sure it touches the right side of the note head
      // Position varies based on note type
      double stemX;
      if (note.type == 'quarter') {
        // For quarter notes (p-shape) - slighly to the left of center
        stemX = x - noteSize/12.0;
      } else if (note.type == 'half') {
        // For half notes - position more to the right but not as far as before
        stemX = x - noteSize/8.0;
      } else {
        // For other notes with stem down
        stemX = x - noteSize/1.0;
      }
      
      canvas.drawLine(
        Offset(stemX, y + noteSize/9),
        Offset(stemX, y + actualStemLength),
        stemPaint,
      );
    }
  }

  void _drawFlag(Canvas canvas, double x, double y, Note note, Paint paint) {
    // Determine stem direction based on note position relative to the middle line
    final middleLineY = staffStartY + (staffSpacing * 2);
    
    // Use the same stem direction logic as in _drawStem
    bool stemUp;
    if (note.stemDirection == 'up') {
      stemUp = true;
    } else if (note.stemDirection == 'down') {
      stemUp = false;
    } else if (note.type == 'quarter') {
      // For quarter notes: above middle line = stem down, below = stem up
      stemUp = y >= middleLineY;
    } else {
      // Default for other notes: use explicit direction from MusicXML or calculate
      stemUp = note.stemDirection == 'up' || (note.stemDirection != 'down' && y >= middleLineY);
    }
    
    // Get stem X position - must match _drawStem positioning
    double stemX;
    if (!stemUp && note.type == 'quarter') {
      stemX = x - noteSize/12.0; // For quarter notes with stem down (p-shape)
    } else if (!stemUp && note.type == 'half') {
      stemX = x - noteSize/8.0; // For half notes with stem down
    } else if (stemUp) {
      stemX = x + noteSize/9.0; // For stem up
    } else {
      stemX = x - noteSize/1.0; // For other notes with stem down
    }
    
    // Use the same stem length calculation as _drawStem
    double actualStemLength = stemLength * 0.65;
    if (y < staffStartY - staffSpacing * 1.5 || y > staffStartY + staffSpacing * 5.5) {
      actualStemLength += staffSpacing * 0.5;
    }

    if (note.type == 'eighth') {
      final flagPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = lineWidth * 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      if (stemUp) {
        // Starting point exactly at stem end
        final startX = stemX;
        final startY = y - actualStemLength;
        
        // Draw S-shaped flag starting right at stem end
        final path = Path();
        path.moveTo(startX, startY);
        
        // Adjusted curves to start right at stem end
        path.quadraticBezierTo(
          startX + noteSize * 0.10, startY + noteSize * 0.15,
          startX + noteSize * 0.4, startY + noteSize * 0.32
        );
        path.quadraticBezierTo(
          startX + noteSize * 0.5, startY + noteSize * 0.55,
          startX + noteSize * 0.3, startY + noteSize * 0.7
        );
        
        canvas.drawPath(path, flagPaint);
      } else {
        // Starting point exactly at stem end
        final startX = stemX;
        final startY = y + actualStemLength;
        
        // Draw inverted S-shaped flag starting right at stem end
        final path = Path();
        path.moveTo(startX, startY);
        
        // Adjusted curves to start right at stem end
        path.quadraticBezierTo(
          startX - noteSize * 0.4, startY - noteSize * 0.15,
          startX - noteSize * 0.3, startY - noteSize * 0.35
        );
        path.quadraticBezierTo(
          startX - noteSize * 0.5, startY - noteSize * 0.55,
          startX - noteSize * 0.2, startY - noteSize * 0.7
        );
        
        canvas.drawPath(path, flagPaint);
      }
    } else if (note.type == '16th') {
      final text = stemUp ? BravuraFont.flag16thUp : BravuraFont.flag16thDown;

      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Bravura',
            fontSize: noteSize * 1.2,
            height: 1.0,
            color: Colors.black,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      
      // Adjusted to connect perfectly with stem
      final xPos = stemUp ? 
                  stemX - textPainter.width/2 :
                  stemX - textPainter.width/2;
      final yPos = stemUp ? 
                  y - actualStemLength :  // Start right at stem end
                  y + actualStemLength - textPainter.height;  // Start right at stem end
      
      canvas.save();
      canvas.translate(xPos + textPainter.width/2, yPos + textPainter.height/2);
      canvas.rotate(stemUp ? 0.05 : -0.05);
      canvas.translate(-(xPos + textPainter.width/2), -(yPos + textPainter.height/2));
      
      textPainter.paint(canvas, Offset(xPos, yPos));
      canvas.restore();
    }
  }

  void _drawRest(Canvas canvas, double x, double y, Note note, Paint paint) {
    // Standardized rest positions - ignoring the y-value passed in
    // Rests are always positioned on fixed positions of the staff
    double restY = staffStartY + staffSpacing * 2; // Default: Middle line
    double fontSize = noteSize * 0.95; // Base font size for rests
    
    // Adjust rest position and size based on type
    switch (note.type) {
      case 'whole':
        restY = staffStartY + staffSpacing; // Fourth line from bottom
        fontSize *= 0.9; // Slightly smaller
        break;
      case 'half':
        restY = staffStartY + staffSpacing * 1.5; // Third space from bottom
        fontSize *= 0.9; // Slightly smaller
        break;
      case 'quarter':
        restY = staffStartY + staffSpacing * 2; // Middle line
        fontSize *= 1.1; // Slightly larger
        break;
      case 'eighth':
        restY = staffStartY + staffSpacing * 2.5; // Third space from top
        fontSize *= 1.0;
        break;
      case '16th':
        restY = staffStartY + staffSpacing * 2.5; // Third space from top
        fontSize *= 1.05; // Slightly larger for visibility
        break;
    }

    final text = note.type == 'whole' ? BravuraFont.restWhole :
                note.type == 'half' ? BravuraFont.restHalf :
                note.type == 'quarter' ? BravuraFont.restQuarter :
                note.type == 'eighth' ? BravuraFont.rest8th :
                note.type == '16th' ? BravuraFont.rest16th :
                BravuraFont.restQuarter;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Bravura',
          fontSize: fontSize,
          height: 1.0,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Center the rest horizontally and position vertically
    final restX = x - textPainter.width / 2;
    final adjustedY = restY - textPainter.height / 2;
    
    // For whole and half rests, ensure they sit precisely on the line
    if (note.type == 'whole' || note.type == 'half') {
      paint.style = PaintingStyle.fill;
      paint.strokeWidth = lineWidth;
    }
    
    textPainter.paint(canvas, Offset(restX, adjustedY));
    
    // Draw augmentation dot if needed
    if (note.hasDot) {
      // Check if the rest is on a staff line
      bool isOnStaffLine = false;
      
      // Rests on staff lines have Y positions that align with staff lines
      for (int i = 0; i <= 4; i++) {
        double staffLineY = staffStartY + (i * staffSpacing);
        if ((restY - staffLineY).abs() < 1.5) {
          isOnStaffLine = true;
          break;
        }
      }
      
      // Adjust dot position - move up if rest is on a line
      double dotY = restY;
      if (isOnStaffLine) {
        dotY -= staffSpacing / 2; // Move dot up to the space above
      }
      
      _drawDot(canvas, restX + textPainter.width - 2, dotY, paint);
    }
  }

  void _drawAccidental(Canvas canvas, double x, double y, int alter, Paint paint) {
    final text = alter == 2 ? BravuraFont.accidentalDoubleSharp :
                alter == -2 ? BravuraFont.accidentalDoubleFlat :
                alter == 1 ? BravuraFont.accidentalSharp :
                alter == -1 ? BravuraFont.accidentalFlat :
                BravuraFont.accidentalNatural;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Bravura',
          fontSize: noteSize * 0.85, // Slightly smaller than note
          height: 1.0,
          color: const Color(0xFF8B4511),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    // Position accidental with proper spacing from note
    final spacing = 1.0; // Reduced from 3 for tighter spacing between accidental and note
    final accX = x - textPainter.width - spacing;
    
    // Calculate vertical position, with adjustments for different accidental types
    final accY = y - textPainter.height / 2;
    
    // Calculate vertical offset based on accidental type and position
    double verticalOffset = 0.0;
    if (alter == -1) {
      // For flats
      verticalOffset = -1.0;
    } else if (alter == 1) {
      // For sharps
      verticalOffset = -0.5;
    } else if (alter == 2) {
      // For double sharps - align with single sharp position
      verticalOffset = -0.5;
    } else if (alter == -2) {
      // For double flats - align with single flat position
      verticalOffset = -1.0;
    }
    
    // Horizontal adjustment for better alignment
    final horizontalOffset = alter == 1 || alter == 2 ? 1.0 : 0.0;
    
    canvas.save();
    // Slight rotation for more natural appearance
    canvas.translate(accX + textPainter.width/2 + horizontalOffset, accY + textPainter.height/2);
    canvas.rotate(alter == 1 || alter == 2 ? 0.02 : -0.02);
    canvas.translate(-(accX + textPainter.width/2 + horizontalOffset), -(accY + textPainter.height/2));
    
    textPainter.paint(canvas, Offset(accX + horizontalOffset, accY + verticalOffset));
    canvas.restore();
  }

  void _drawDot(Canvas canvas, double x, double y, Paint paint) {
    paint.style = PaintingStyle.fill;
    
    // Draw main dot - position closer to the note
    canvas.drawCircle(
      Offset(x - 2, y), // Now using a negative offset to move it to the left
      2.2, // Slightly larger dot
      paint,
    );
    
    // For double dots in future implementation
    if (false) { // Placeholder for future double-dot support
      canvas.drawCircle(
        Offset(x + 3, y), // Also adjusted for spacing from first dot
        2.2,
        paint,
      );
    }
  }

  bool _shouldSlurBeAbove(List<Note> notes) {
    // Count notes with stems up and down
    int stemsUp = 0;
    int stemsDown = 0;
    
    for (final note in notes) {
      // Get note's position relative to middle line
      final noteY = _getNoteY(note, staffStartY);
      final middleLineY = staffStartY + (staffSpacing * 2);
      
      // Notes above middle line typically have stems down
      if (noteY < middleLineY) {
        stemsDown++;
      } else {
        stemsUp++;
      }
    }
    
    // If equal, default to above
    return stemsDown >= stemsUp;
  }

  void _drawSlurs(Canvas canvas, double x, double y, Note note, Paint paint) {
    final middleLineY = staffStartY + (staffSpacing * 2);
    final stemUp = y >= middleLineY;

    for (final slur in note.slurs) {
      if (slur.type == 'start') {
        // Store start position with the slur number
        _slurStartPositions[slur.number] = {
          'x': x + (stemUp ? noteSize/3 : noteSize/3),
          'y': y + (stemUp ? noteSize/3 : -noteSize/3),
          'stemUp': stemUp ? 1.0 : -1.0
        };
      } else if (slur.type == 'stop') {
        final startPos = _slurStartPositions[slur.number];
        if (startPos != null) {
          final startX = startPos['x']!;
          final startY = startPos['y']!;
          final startStemUp = startPos['stemUp']!;
          
          // Get all notes involved in this slur
          final slurredNotes = _slurNotes[slur.number] ?? [];
          final slurAbove = _shouldSlurBeAbove(slurredNotes);
          
          // Calculate end position
          final endX = x - noteSize/3;
          final endY = y + (stemUp ? noteSize/3 : -noteSize/3);
          
          final path = Path();
          final dx = endX - startX;
          final dy = endY - startY;
          
          // Adjust curve height based on distance and whether slur is above or below
          final curveHeight = (dx / 80.0).clamp(20.0, 40.0);
          final direction = slurAbove ? -1.0 : 1.0; // Invert direction based on slur position
          
          // Start the slur curve
          path.moveTo(startX, startY);
          
          // Adjust control points based on slur direction
          final controlY = slurAbove ? 
              math.min(startY, endY) - curveHeight : // Above notes
              math.max(startY, endY) + curveHeight;  // Below notes
          
          path.cubicTo(
            startX + dx/3,     // First control point X
            controlY,          // First control point Y
            startX + dx*2/3,   // Second control point X
            controlY,          // Second control point Y
            endX,              // End point X
            endY               // End point Y
          );
          
          final slurPaint = Paint()
            ..color = Colors.black
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
          
          canvas.drawPath(path, slurPaint);
          
          // Remove the start position after drawing
          _slurStartPositions.remove(slur.number);
        }
      }
    }
  }

  void _drawLedgerLines(Canvas canvas, double x, double y, double startY, Paint paint) {
    final staffTop = startY;
    final staffBottom = startY + (staffSpacing * 4);
    paint.strokeWidth = lineWidth;
    
    // Draw ledger lines above staff, skipping the first one
    if (y < staffTop - staffSpacing/4) {
      var currentY = staffTop;
      int ledgerCount = -1;
      while (currentY > y - staffSpacing/4) {
        currentY -= staffSpacing;
        ledgerCount++;
        if (ledgerCount > 1) { // Skip the first ledger line
          _drawLedgerLine(canvas, x, currentY, paint);
        }
      }
    }
    
    // Draw ledger lines below staff, skipping the first one
    if (y > staffBottom + staffSpacing/4) {
      var currentY = staffBottom;
      int ledgerCount = -1;
      while (currentY < y + staffSpacing/4) {
        currentY += staffSpacing;
        ledgerCount++;
        if (ledgerCount > 1) { // Skip the first ledger line
          _drawLedgerLine(canvas, x, currentY, paint);
        }
      }
    }

    // Special case for middle C
    if (y >= staffBottom + staffSpacing * 0.75 && y <= staffBottom + staffSpacing * 1.25) {
      _drawLedgerLine(canvas, x, staffBottom + staffSpacing, paint);
    }
  }

  void _drawLedgerLine(Canvas canvas, double x, double y, Paint paint) {
    canvas.drawLine(
      Offset(x - ledgerLineLength/2, y),
      Offset(x + ledgerLineLength/2, y),
      paint,
    );
  }

  double _getNoteY(Note note, double startY) {
    // Standard music notation positioning following the staff pattern:
    // Each line and space represents a specific note, moving up the scale
    // Lines from bottom to top: E4, G4, B4, D5, F5
    // Spaces from bottom to top: F4, A4, C5, E5
    final stepOrder = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    
    // Position of middle C (C4) - one ledger line below the staff
    final middleC = startY + (staffSpacing * 5);
    
    // Calculate steps from middle C
    int stepsFromMiddleC = 0;
    
    // Calculate octave difference
    int octaveDiff = note.octave - 4; // relative to C4
    stepsFromMiddleC += octaveDiff * 7; // 7 steps per octave
    
    // Add steps within the octave
    int currentStepIndex = stepOrder.indexOf(note.step);
    int middleCIndex = stepOrder.indexOf('C');
    stepsFromMiddleC += currentStepIndex - middleCIndex;
    
    // Each step is half a staff space
    // Moving up the staff means subtracting from the Y coordinate
    return middleC - (stepsFromMiddleC * staffSpacing / 2);
  }

  void _drawBeam(Canvas canvas, List<Map<String, dynamic>> notePositions, List<int> group, Paint paint) {
    if (group.length < 2) return;
    
    // Get the note positions for the beam group
    final firstNote = notePositions[group.first];
    final lastNote = notePositions[group.last];
    
    // Get the first and last note objects
    final firstNoteObj = firstNote['note'];
    final lastNoteObj = lastNote['note'];
    
    // For background painter, we don't need to implement full beam drawing
    // Just return early since beams are part of static rendering
    return;
  }

  // Returns true if the note's step is sharped/flatted in the key signature
  bool _isAccidentalInKeySignature(Note note) {
    // Only handle sharps for now (positive keySharps)
    if (score.keySharps > 0) {
      // Order of sharps in key signature for treble clef
      const sharpOrder = ['F', 'C', 'G', 'D', 'A', 'E', 'B'];
      for (int i = 0; i < score.keySharps && i < sharpOrder.length; i++) {
        if (note.step == sharpOrder[i]) return true;
      }
    }
    // TODO: Add flats support if needed
    return false;
  }
}

class MusicSheetOverlayPainter extends CustomPainter {
  final Score score;
  final double currentX;
  final bool isPlaying;
  final int currentNoteIndex;
  final double currentTime;
  final double bpm;
  final bool isCorrect;
  
  // Standard music engraving measurements (shared constants)
  static const double staffSpacing = 10.0;
  static const double lineWidth = 1.2;
  static const double noteSize = 24.0;
  static const double stemLength = 40.0;
  static const double measureWidth = 160.0;
  static const double staffStartX = 80.0;
  static const double staffStartY = 50.0;

  MusicSheetOverlayPainter({
    required this.score,
    required this.currentX,
    required this.isPlaying,
    required this.currentNoteIndex,
    required this.currentTime,
    required this.bpm,
    required this.isCorrect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isPlaying) return; // Only draw overlay when playing
    
    // Draw only the note highlighting overlay
    _drawNoteHighlights(canvas, size);
  }

  void _drawNoteHighlights(Canvas canvas, Size size) {
    final staffHeight = staffSpacing * 4;
    final measureCount = score.measures.length;
    final totalWidth = size.width - 180.0;
    
    // Calculate measure widths (same logic as background painter)
    List<double> measureWidths = [];
    
    for (int m = 0; m < measureCount; m++) {
      final measure = score.measures[m];
      final noteCount = measure.notes.length;
      double width = 160.0;
      
      if (noteCount >= 6) {
        width += 40.0;
      }
      final eighthNotes = measure.notes.where((n) => 
        n.type == 'eighth' || n.type == '16th'
      ).length;
      if (eighthNotes >= 4) {
        width += eighthNotes * 5.0;
      }
      
      width = width.clamp(160.0, 240.0);
      measureWidths.add(width);
    }
    
    final requestedTotalWidth = measureWidths.reduce((a, b) => a + b);
    final scaleFactor = (totalWidth / requestedTotalWidth).clamp(0.85, 1.2);
    for (int i = 0; i < measureWidths.length; i++) {
      measureWidths[i] *= scaleFactor;
    }
    
    double currentX = staffStartX + 80.0;

    // Find and highlight the current note
    for (int m = 0; m < measureCount; m++) {
      final measure = score.measures[m];
      final measureWidth = measureWidths[m];
      
      final noteCount = measure.notes.length;
      double noteSpacing = measureWidth / (noteCount + 1);
      
      if (noteCount > 1) {
        final longNotes = measure.notes.where((n) => 
          n.type == 'whole' || 
          n.type == 'half' || 
          (n.type == 'quarter' && n.hasDot)
        ).length;
        final shortNotes = noteCount - longNotes;
        
        noteSpacing = ((measureWidth - 60) / (noteCount + 0.5)).clamp(30.0, 75.0);
        
        if (longNotes > 0) noteSpacing += 8.0;
        if (shortNotes > 2) noteSpacing -= 4.0;
        if (shortNotes > 4) noteSpacing -= 2.0;
        
        if (shortNotes == noteCount && noteCount >= 6) {
          noteSpacing = (measureWidth - 50) / (noteCount + 0.5);
        }
      }

      double noteX = currentX + 25.0;
      
      if (measure.notes.length >= 6) {
        noteX = currentX + 20.0;
      }
      
      for (int i = 0; i < measure.notes.length; i++) {
        final note = measure.notes[i];
        final noteY = _getNoteY(note, staffStartY);
        
        // Calculate if this is the current note
        int totalNoteIndex = 0;
        double totalBeats = 0.0;

        // Calculate total beats up to this note
        for (int prevM = 0; prevM < m; prevM++) {
          final prevMeasure = score.measures[prevM];
          for (final prevNote in prevMeasure.notes) {
            totalBeats += _getNoteDuration(prevNote);
          }
        }

        for (int prevI = 0; prevI < i; prevI++) {
          totalBeats += _getNoteDuration(measure.notes[prevI]);
        }

        // Check if this is the current note
        const double secondsPerMinute = 60.0;
        final double beatDuration = secondsPerMinute / bpm;
        final double currentBeats = currentTime / beatDuration;
        
        final bool isCurrentNote = currentBeats >= totalBeats && 
                                 currentBeats < totalBeats + _getNoteDuration(note);

        // Draw highlight if this is the current note and not a rest
        if (isCurrentNote && !note.isRest) {
          // Draw the highlight circle
          final highlightPaint = Paint()
            ..color = isCorrect ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)
            ..style = PaintingStyle.fill;
          
          canvas.drawCircle(
            Offset(noteX, noteY),
            noteSize * 0.8,
            highlightPaint,
          );

          // Add a glow effect
          final glowPaint = Paint()
            ..color = isCorrect ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
          
          canvas.drawCircle(
            Offset(noteX, noteY),
            noteSize * 1.5,
            glowPaint,
          );
        }
        
        noteX += noteSpacing;
      }
      
      currentX += measureWidth;
    }
  }

  double _getNoteY(Note note, double startY) {
    final stepOrder = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    final middleC = startY + (staffSpacing * 5);
    
    int stepsFromMiddleC = 0;
    int octaveDiff = note.octave - 4;
    stepsFromMiddleC += octaveDiff * 7;
    
    int currentStepIndex = stepOrder.indexOf(note.step);
    int middleCIndex = stepOrder.indexOf('C');
    stepsFromMiddleC += currentStepIndex - middleCIndex;
    
    return middleC - (stepsFromMiddleC * staffSpacing / 2);
  }

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
        return 1.0;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! MusicSheetOverlayPainter) return true;
    
    // Only repaint when playback state changes
    return oldDelegate.currentTime != this.currentTime ||
           oldDelegate.isPlaying != this.isPlaying ||
           oldDelegate.currentNoteIndex != this.currentNoteIndex ||
           oldDelegate.isCorrect != this.isCorrect ||
           oldDelegate.bpm != this.bpm;
  }
}
