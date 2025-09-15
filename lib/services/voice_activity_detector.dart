import 'dart:math';
import 'dart:typed_data';

/// Lightweight Voice Activity Detector using short-time energy and zero-crossing rate.
///
/// Sensitivity in [0..1]: higher values are more sensitive (easier to trigger voice).
class VoiceActivityDetector {
	final double sensitivity; // 0..1
	final int sampleRate;

	// EMA of noise energy to adapt thresholds over time.
	double _noiseEnergy = 1e-6;
	bool _initialized = false;
	final double _emaAlpha = 0.05;

	VoiceActivityDetector({
		required this.sampleRate,
		double sensitivity = 0.6,
	}) : sensitivity = sensitivity.clamp(0.0, 1.0);

	/// Compute zero crossing rate for the frame.
	double _zcr(Float64List x) {
		if (x.length < 2) return 0.0;
		int count = 0;
		for (int i = 1; i < x.length; i++) {
			if ((x[i - 1] >= 0 && x[i] < 0) || (x[i - 1] < 0 && x[i] >= 0)) {
				count++;
			}
		}
		return count / (x.length - 1);
	}

	/// Decide if the frame contains voice.
	bool isVoice(Float64List frame) {
		if (frame.isEmpty) return false;

		double energy = 0.0;
		for (int i = 0; i < frame.length; i++) {
			final double s = frame[i];
			energy += s * s;
		}
		energy /= max(frame.length, 1);

		if (!_initialized) {
			_noiseEnergy = energy + 1e-8;
			_initialized = true;
		}

		// Update noise estimate conservatively (only when energy is near noise).
		final double energyVsNoise = energy / (_noiseEnergy + 1e-9);
		if (energyVsNoise < 1.5) {
			_noiseEnergy = _emaAlpha * energy + (1.0 - _emaAlpha) * _noiseEnergy;
		}

		// Adaptive thresholds.
		final double zcrVal = _zcr(frame);
		final double energyThresh = (1.5 - 0.8 * sensitivity) * _noiseEnergy;
		final double zcrVoiceMax = 0.25 + 0.15 * (1.0 - sensitivity); // voiced tends to lower ZCR than pure noise

		final bool energyVoice = energy > energyThresh;
		final bool zcrVoice = zcrVal < zcrVoiceMax;
		return energyVoice && zcrVoice;
	}
} 