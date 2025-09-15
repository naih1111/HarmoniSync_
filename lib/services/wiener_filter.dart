import 'dart:typed_data';
import 'dart:math';

/// Lightweight Wiener-like noise reducer for real-time frames.
///
/// This implementation operates in the time domain to avoid FFT dependencies.
/// It maintains a running estimate of the noise floor using an exponential
/// moving average of frame energy during presumed non-voice periods.
///
/// API notes:
/// - Call [apply] on each PCM16 frame (little-endian) to obtain a cleaned
///   Float64List normalized to [-1, 1].
/// - Optionally call [updateNoiseFromNonVoice] with the same frame to refine
///   noise estimate when VAD reports non-voice.
/// - The [strength] parameter controls aggressiveness (0.0..1.0).
class WienerFilter {
	/// Aggressiveness of suppression [0..1]. Higher removes more but risks artifacts.
	final double strength;

	/// EMA factor for tracking noise energy.
	final double noiseEmaAlpha;

	/// Floor to avoid complete attenuation.
	final double gainFloor;

	double _noiseEnergy; // running estimate of noise energy (mean square)
	bool _initialized = false;

	WienerFilter({
		double strength = 0.5,
		double noiseEmaAlpha = 0.05,
		double gainFloor = 0.15,
	})  : strength = strength.clamp(0.0, 1.0),
			noiseEmaAlpha = noiseEmaAlpha.clamp(0.001, 0.5),
			gainFloor = gainFloor.clamp(0.0, 0.9),
			_noiseEnergy = 1e-6;

	/// Converts PCM16 LE bytes to normalized Float64 samples [-1, 1].
	Float64List _bytesToFloat64(Uint8List audioData) {
		final int length = audioData.length ~/ 2;
		final Float64List buffer = Float64List(length);
		final ByteData view = ByteData.sublistView(audioData);
		for (int i = 0; i < length; i++) {
			final int sample = view.getInt16(i * 2, Endian.little);
			buffer[i] = sample / 32768.0;
		}
		return buffer;
	}

	/// Updates the running noise energy estimate using an EMA.
	void _updateNoiseEnergy(Float64List frame) {
		double energy = 0.0;
		for (int i = 0; i < frame.length; i++) {
			final double s = frame[i];
			energy += s * s;
		}
		energy /= max(frame.length, 1);

		if (!_initialized) {
			_noiseEnergy = energy + 1e-8;
			_initialized = true;
			return;
		}

		_noiseEnergy = noiseEmaAlpha * energy + (1.0 - noiseEmaAlpha) * _noiseEnergy;
	}

	/// Applies a time-domain Wiener-like gain to the frame based on estimated SNR.
	/// Returns a new Float64List with the cleaned samples.
	Float64List apply(Uint8List pcm16LeFrame) {
		final Float64List x = _bytesToFloat64(pcm16LeFrame);
		if (x.isEmpty) return x;

		// Estimate signal energy for this frame.
		double signalEnergy = 0.0;
		for (int i = 0; i < x.length; i++) {
			final double s = x[i];
			signalEnergy += s * s;
		}
		signalEnergy /= max(x.length, 1);

		// Initialize noise on first frame if needed.
		if (!_initialized) {
			_noiseEnergy = signalEnergy + 1e-8;
			_initialized = true;
		}

		// Posterior SNR estimate.
		final double snr = max(0.0, signalEnergy - _noiseEnergy) / (_noiseEnergy + 1e-9);
		// Wiener gain: G = SNR / (SNR + 1). Add strength to control aggressiveness.
		double gain = snr / (snr + 1.0);
		gain = gainFloor + (1.0 - gainFloor) * pow(gain, 1.0 + 2.0 * strength);

		final Float64List y = Float64List(x.length);
		for (int i = 0; i < x.length; i++) {
			y[i] = (x[i] * gain).clamp(-1.0, 1.0);
		}
		return y;
	}

	/// Call this when VAD says the frame is non-voice to refine noise estimate.
	void updateNoiseFromNonVoice(Float64List cleanedFrame) {
		_updateNoiseEnergy(cleanedFrame);
	}
} 