import 'dart:typed_data';

class YinAlgorithm {
  static double? detectPitch(Uint8List audioData, int sampleRate) {
    final length = audioData.length ~/ 2;
    if (length < 2) return null;

    final Float64List audioBuffer = Float64List(length);
    final ByteData byteData = ByteData.sublistView(audioData);

    for (int i = 0; i < length; i++) {
      final int sample = byteData.getInt16(i * 2, Endian.little);
      audioBuffer[i] = sample / 32768.0;
    }

    final double threshold = 0.10;
    final int bufferSize = audioBuffer.length;
    final int maxLag = bufferSize ~/ 2;
    final Float64List difference = Float64List(maxLag);

    for (int lag = 1; lag < maxLag; lag++) {
      double sum = 0;
      for (int i = 0; i < maxLag; i++) {
        final double delta = audioBuffer[i] - audioBuffer[i + lag];
        sum += delta * delta;
      }
      difference[lag] = sum;
    }

    final Float64List cmndf = Float64List(maxLag);
    cmndf[0] = 1;
    double runningSum = 0;

    for (int tau = 1; tau < maxLag; tau++) {
      runningSum += difference[tau];
      cmndf[tau] = difference[tau] / ((runningSum / tau) + 1e-6);
    }

    int tauEstimate = -1;
    for (int tau = 2; tau < maxLag - 1; tau++) {
      if (cmndf[tau] < threshold &&
          cmndf[tau] < cmndf[tau - 1] &&
          cmndf[tau] <= cmndf[tau + 1]) {
        tauEstimate = tau;
        break;
      }
    }

    if (tauEstimate != -1) {
      return sampleRate / tauEstimate;
    } else {
      return null;
    }
  }
}
