import 'package:flutter/material.dart';
import '../services/music_service.dart';

/// Widget for displaying a horizontal scrollable row of notes
/// Shows progress through the exercise with color-coded feedback
class NoteProgressRow extends StatefulWidget {
  final Score score;
  final int currentNoteIndex;
  final Map<int, bool> noteCorrectness;
  final bool isCorrect;
  final double pitchConfidence;
  final ScrollController? scrollController;

  const NoteProgressRow({
    super.key,
    required this.score,
    required this.currentNoteIndex,
    required this.noteCorrectness,
    required this.isCorrect,
    required this.pitchConfidence,
    this.scrollController,
  });

  @override
  State<NoteProgressRow> createState() => _NoteProgressRowState();
}

class _NoteProgressRowState extends State<NoteProgressRow> {
  List<String> _noteNames = [];
  bool _needsRebuild = true;

  @override
  void didUpdateWidget(NoteProgressRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Only rebuild note names if score actually changed
    if (oldWidget.score != widget.score) {
      _needsRebuild = true;
    }
  }

  /// Build the list of note names from the score
  void _buildNoteNames() {
    if (!_needsRebuild && _noteNames.isNotEmpty) return;
    
    _noteNames.clear();
    for (final measure in widget.score.measures) {
      for (final note in measure.notes) {
        if (!note.isRest) {
          _noteNames.add("${note.step}${note.octave}");
        }
      }
    }
    _needsRebuild = false;
  }

  @override
  Widget build(BuildContext context) {
    _buildNoteNames();

    // Create horizontal scrollable list of notes
    return ListView.separated(
      controller: widget.scrollController,
      scrollDirection: Axis.horizontal,
      itemCount: _noteNames.length,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      separatorBuilder: (context, idx) => const SizedBox(width: 8),
      itemBuilder: (context, idx) {
        // Determine the current state of this note
        final isCurrentNote = idx == widget.currentNoteIndex;
        final wasCorrect = widget.noteCorrectness[idx];
       
        // Choose color based on note status
        Color noteColor;
        Color textColor;
       
        if (isCurrentNote) {
          noteColor = widget.isCorrect ? Colors.green : Colors.red;
          textColor = const Color(0xFFF5F5DD);
        } else if (wasCorrect != null) {
          noteColor = wasCorrect ? Colors.green : Colors.red;
          textColor = const Color(0xFFF5F5DD);
        } else {
          noteColor = const Color(0xFFF5F5DD);
          textColor = const Color(0xFF8B4511);
        }

        // Add confidence indicator for current note
        if (isCurrentNote && widget.pitchConfidence > 0) {
          // Show confidence as border thickness or opacity
          final confidenceOpacity = widget.pitchConfidence.clamp(0.3, 1.0);
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
}