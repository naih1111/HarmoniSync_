import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/note_utils.dart';

class ScoreSheetWidget extends StatelessWidget {
  final String? detectedNote;
  final int currentIndex;

  const ScoreSheetWidget({
    super.key,
    this.detectedNote,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          size: const Size(double.infinity, 180),
          painter: ScoreSheetPainter(detectedNote, currentIndex),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: SvgPicture.asset(
            'assets/treble_clef.svg',
            width: 30,
            height: 60,
          ),
        ),
      ],
    );
  }
}

class ScoreSheetPainter extends CustomPainter {
  final String? detectedNote;
  final int currentIndex;

  ScoreSheetPainter(this.detectedNote, this.currentIndex);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;

    const spacing = 20.0;
    const leftMargin = 16.0;

    // Staff lines
    for (int i = 0; i < 5; i++) {
      double y = spacing * i + spacing + 20;
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width - leftMargin, y), paint);
    }

    final solfegeNotes = ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Ti', 'Do'];
    final noteFrequencies = ['C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5'];

    for (int i = 0; i < solfegeNotes.length; i++) {
      final noteOffset = _getNoteOffset(noteFrequencies[i], spacing);
      final centerX = size.width / 9 * (i + 1);
      final centerY = spacing * 5 - noteOffset + 20;

      Color noteColor = Colors.black;
      if (i == currentIndex && detectedNote != null) {
        if (NoteUtils.frequencyToNote(NoteUtils.noteFrequencies[noteFrequencies[i]]!) == detectedNote) {
          noteColor = Colors.green;
        } else {
          noteColor = Colors.red;
        }
      }

      final notePaint = Paint()..color = noteColor;

      // Draw note circle
      canvas.drawCircle(Offset(centerX, centerY), 9, notePaint);

      // Draw solfege label above the note
      final textPainter = TextPainter(
        text: TextSpan(
          text: solfegeNotes[i],
          style: TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(centerX - 10, centerY - 25));
    }
  }

  double _getNoteOffset(String note, double spacing) {
    final Map<String, int> noteToLine = {
      "C4": 0, "D4": 1, "E4": 2, "F4": 3, "G4": 4,
      "A4": 5, "B4": 6, "C5": 7,
    };
    return spacing * (noteToLine[note]! * 0.5);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
