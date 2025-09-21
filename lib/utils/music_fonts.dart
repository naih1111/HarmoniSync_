/// SMuFL (Standard Music Font Layout) codes for Bravura font
class BravuraFont {
  // Note heads
  static const String noteheadBlack = '\uE0A4';       // Filled notehead (quarter notes and shorter)
  static const String noteheadHalf = '\uE0A3';        // Half note head
  static const String noteheadWhole = '\uE0A2';       // Whole note head
  
  // Stems and flags
  static const String stemUp = '\uE210';              // Upward stem
  static const String stemDown = '\uE211';            // Downward stem
  static const String flag8thUp = '\uE240';           // Eighth note flag (up)
  static const String flag8thDown = '\uE241';         // Eighth note flag (down)
  static const String flag16thUp = '\uE242';          // 16th note flag (up)
  static const String flag16thDown = '\uE243';        // 16th note flag (down)
  
  // Rests
  static const String restWhole = '\uE4E3';           // Whole rest
  static const String restHalf = '\uE4E4';            // Half rest
  static const String restQuarter = '\uE4E5';         // Quarter rest
  static const String rest8th = '\uE4E6';             // Eighth rest
  static const String rest16th = '\uE4E7';            // 16th rest
  
  // Clefs
  static const String trebleClef = '\uE050';          // Treble clef
  static const String bassClef = '\uE062';            // Bass clef
  
  // Accidentals
  static const String accidentalSharp = '\uE262';     // Sharp
  static const String accidentalFlat = '\uE260';      // Flat
  static const String accidentalNatural = '\uE261';   // Natural
  static const String accidentalDoubleSharp = '\uE263'; // Double sharp
  static const String accidentalDoubleFlat = '\uE264';  // Double flat
  
  // Time signatures
  static const String timeSig0 = '\uE080';            // Time signature 0
  static const String timeSig1 = '\uE081';            // Time signature 1
  static const String timeSig2 = '\uE082';            // Time signature 2
  static const String timeSig3 = '\uE083';            // Time signature 3
  static const String timeSig4 = '\uE084';            // Time signature 4
  static const String timeSig5 = '\uE085';            // Time signature 5
  static const String timeSig6 = '\uE086';            // Time signature 6
  static const String timeSig7 = '\uE087';            // Time signature 7
  static const String timeSig8 = '\uE088';            // Time signature 8
  static const String timeSig9 = '\uE089';            // Time signature 9
  
  // Staff lines and barlines
  static const String barlineSingle = '\uE030';       // Single barline
  static const String barlineDouble = '\uE031';       // Double barline
  static const String barlineFinal = '\uE032';        // Final barline
  
  // Dots
  static const String augmentationDot = '\uE1E7';     // Augmentation dot
  
  // Dynamic marks
  static const String dynamicPiano = '\uE520';        // Piano (p)
  static const String dynamicForte = '\uE522';        // Forte (f)
  static const String dynamicMezzo = '\uE521';        // Mezzo (m)
  
  // Get time signature character from number
  static String getTimeSignature(int number) {
    switch (number) {
      case 0: return timeSig0;
      case 1: return timeSig1;
      case 2: return timeSig2;
      case 3: return timeSig3;
      case 4: return timeSig4;
      case 5: return timeSig5;
      case 6: return timeSig6;
      case 7: return timeSig7;
      case 8: return timeSig8;
      case 9: return timeSig9;
      default: return timeSig4; // Default to 4
    }
  }
} 