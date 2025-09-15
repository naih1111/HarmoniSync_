import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import '../lib/services/enhanced_yin.dart';

void main() {
  print('Enhanced YIN Console Test');
  print('=======================');

  // Test with synthetic 440 Hz tone
  final enhanced = EnhancedYin(
    sampleRate: 44100,
    wienerStrength: 0.5,
    vadSensitivity: 0.6,
    medianWindow: 5,
    upsampleFactor: 2,
    enableParabolicRefinement: true,
  );

  // Generate test tone
  const frequency = 440.0;
  const sampleRate = 44100;
  const frameSize = 1024;
  final samples = Uint8List(frameSize * 2);

  for (int i = 0; i < frameSize; i++) {
    final sample = (32767 * math.sin(2 * math.pi * frequency * i / sampleRate)).round();
    samples[i * 2] = sample & 0xFF;
    samples[i * 2 + 1] = (sample >> 8) & 0xFF;
  }

  final pitch = enhanced.processFrame(samples, sampleRate);
  print('Input: ${frequency}Hz');
  print('Detected: ${pitch?.toStringAsFixed(2) ?? 'null'}Hz');
  print('Error: ${pitch != null ? (pitch - frequency).abs().toStringAsFixed(2) : 'N/A'}Hz');
} 